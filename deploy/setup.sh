#!/usr/bin/env bash
#
# Развёртывание stocks_products на чистом Ubuntu 22.04 / 24.04:
# PostgreSQL + gunicorn (systemd) + nginx.
#
# Запуск на сервере от root:
#   bash setup.sh https://github.com/<you>/<repo>.git [домен-или-IP]
#
# Повторный запуск обновляет код (git pull), зависимости, миграции и статику;
# пароль базы и SECRET_KEY при этом сохраняются.

set -euo pipefail

REPO_URL="${1:?Укажите ссылку на git-репозиторий: bash setup.sh https://github.com/<you>/<repo>.git}"
SERVER_NAME="${2:-}"

APP=stocks_products
APP_USER=django
APP_HOME=/srv/$APP
SRC_DIR=$APP_HOME/src
VENV=$APP_HOME/venv
STATIC_ROOT=/var/www/$APP/static
ENV_FILE=/etc/$APP.env
SOCKET_DIR=/run/$APP
DB_NAME=$APP
DB_USER=$APP

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mОшибка: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "запустите от root (или через sudo)"
HAS_SYSTEMD=0
[ -d /run/systemd/system ] && HAS_SYSTEMD=1

log "Устанавливаю пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q python3-venv python3-pip postgresql nginx git curl

if [ -z "$SERVER_NAME" ]; then
    SERVER_NAME="$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
fi
[ -n "$SERVER_NAME" ] || die "не удалось определить IP сервера, передайте его вторым аргументом"
log "Адрес сайта: http://$SERVER_NAME"

log "Пользователь $APP_USER"
id "$APP_USER" >/dev/null 2>&1 || useradd --system --create-home --home-dir "$APP_HOME" --shell /bin/bash "$APP_USER"
mkdir -p "$APP_HOME" "$STATIC_ROOT"
chown "$APP_USER:$APP_USER" "$APP_HOME" "$STATIC_ROOT"

as_app() { runuser -u "$APP_USER" -- "$@"; }

log "Код из $REPO_URL"
if [ -d "$SRC_DIR/.git" ]; then
    as_app git -C "$SRC_DIR" remote set-url origin "$REPO_URL"
    as_app git -C "$SRC_DIR" pull --ff-only
else
    as_app git clone "$REPO_URL" "$SRC_DIR"
fi

# manage.py может лежать в корне репозитория или во вложенной папке
MANAGE_PY="$(find "$SRC_DIR" -maxdepth 3 -name manage.py -not -path '*/.git/*' | head -n 1)"
[ -n "$MANAGE_PY" ] || die "в репозитории не найден manage.py"
PROJECT_DIR="$(dirname "$MANAGE_PY")"
[ -f "$PROJECT_DIR/requirements.txt" ] || die "рядом с manage.py нет requirements.txt"
log "Проект: $PROJECT_DIR"

log "Виртуальное окружение и зависимости"
[ -x "$VENV/bin/python" ] || as_app python3 -m venv "$VENV"
as_app "$VENV/bin/pip" install -q --upgrade pip
as_app "$VENV/bin/pip" install -q -r "$PROJECT_DIR/requirements.txt"
as_app "$VENV/bin/pip" install -q gunicorn

log "PostgreSQL"
if [ "$HAS_SYSTEMD" -eq 1 ]; then
    systemctl enable --now postgresql
else
    service postgresql start
fi

# секреты переживают повторный запуск
SECRET_KEY=""
DB_PASSWORD=""
if [ -f "$ENV_FILE" ]; then
    SECRET_KEY="$(grep -E '^DJANGO_SECRET_KEY=' "$ENV_FILE" | cut -d= -f2- || true)"
    DB_PASSWORD="$(grep -E '^DB_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)"
fi
[ -n "$SECRET_KEY" ] || SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"
[ -n "$DB_PASSWORD" ] || DB_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"

psql_admin() { runuser -u postgres -- psql -v ON_ERROR_STOP=1 -qtA "$@"; }
if [ "$(psql_admin -c "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'")" != "1" ]; then
    psql_admin -c "CREATE ROLE $DB_USER LOGIN"
fi
psql_admin -c "ALTER ROLE $DB_USER PASSWORD '$DB_PASSWORD'"
if [ "$(psql_admin -c "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'")" != "1" ]; then
    psql_admin -c "CREATE DATABASE $DB_NAME OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0 LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8'"
fi

log "Настройки в $ENV_FILE"
cat > "$ENV_FILE" <<EOF
DJANGO_SECRET_KEY=$SECRET_KEY
DJANGO_DEBUG=0
DJANGO_ALLOWED_HOSTS=$SERVER_NAME,localhost,127.0.0.1
DJANGO_CSRF_TRUSTED_ORIGINS=http://$SERVER_NAME,https://$SERVER_NAME
DJANGO_STATIC_ROOT=$STATIC_ROOT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_HOST=127.0.0.1
DB_PORT=5432
EOF
chown root:"$APP_USER" "$ENV_FILE"
chmod 640 "$ENV_FILE"

manage() {
    as_app env -C "$PROJECT_DIR" bash -c 'set -a; . "$0"; set +a; exec "$1" manage.py "${@:2}"' \
        "$ENV_FILE" "$VENV/bin/python" "$@"
}

log "Миграции и статика"
manage migrate --noinput
manage collectstatic --noinput -v 0
manage check

if [ -n "${DJANGO_SUPERUSER_USERNAME:-}" ] && [ -n "${DJANGO_SUPERUSER_PASSWORD:-}" ]; then
    log "Суперпользователь $DJANGO_SUPERUSER_USERNAME"
    manage createsuperuser --noinput --email "${DJANGO_SUPERUSER_EMAIL:-admin@example.com}" \
        --username "$DJANGO_SUPERUSER_USERNAME" 2>/dev/null || echo "уже существует"
fi

log "gunicorn (systemd-сервис $APP)"
cat > /etc/systemd/system/$APP.service <<EOF
[Unit]
Description=gunicorn для $APP
After=network.target postgresql.service

[Service]
User=$APP_USER
Group=www-data
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$ENV_FILE
RuntimeDirectory=$APP
ExecStart=$VENV/bin/gunicorn --workers 3 --bind unix:$SOCKET_DIR/gunicorn.sock --umask 007 --access-logfile - stocks_products.wsgi:application
Restart=always

[Install]
WantedBy=multi-user.target
EOF

log "nginx"
LISTEN_V6=""
[ -f /proc/net/if_inet6 ] && LISTEN_V6="listen [::]:80 default_server;"
cat > /etc/nginx/sites-available/$APP <<EOF
server {
    listen 80 default_server;
    $LISTEN_V6
    server_name $SERVER_NAME;

    client_max_body_size 10M;

    location /static/ {
        alias $STATIC_ROOT/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$SOCKET_DIR/gunicorn.sock;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/$APP /etc/nginx/sites-enabled/$APP
nginx -t

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    log "Открываю порты в ufw"
    ufw allow OpenSSH
    ufw allow 'Nginx Full'
fi

if [ "$HAS_SYSTEMD" -eq 0 ]; then
    log "systemd не найден: конфиги записаны, запустите gunicorn и nginx вручную"
    exit 0
fi

log "Запускаю сервисы"
systemctl daemon-reload
systemctl enable "$APP" >/dev/null
systemctl restart "$APP"
systemctl enable nginx >/dev/null
systemctl restart nginx

sleep 2
CODE="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $SERVER_NAME" http://127.0.0.1/api/v1/ || true)"
if [ "$CODE" = "200" ]; then
    log "Готово! Сайт работает: http://$SERVER_NAME/api/v1/"
else
    die "сайт ответил кодом $CODE. Логи: journalctl -u $APP -n 50 и /var/log/nginx/error.log"
fi
echo "Админка: http://$SERVER_NAME/admin/ (суперпользователь: см. README)"
