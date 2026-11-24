# Склады и запасы — CRUD на Django REST Framework + деплой на VPS

Домашние задания курса Нетологии:

- [CRUD: Склады и запасы](https://github.com/netology-code/dj-homeworks/tree/drf/3.2-crud/stocks_products) — REST API для продуктов и складов;
- [Развертывание проекта](https://github.com/netology-code/py-homeworks-web/tree/new/1.2-deploy) — этот проект, развёрнутый на сервере (PostgreSQL + gunicorn + nginx).

## Что реализовано

- CRUD продуктов: `/api/v1/products/`, поиск по названию и описанию: `?search=помидор`;
- CRUD складов с позициями: `/api/v1/stocks/`. Создание и обновление позиций — во вложенном сериализаторе (`update_or_create`);
- поиск складов по продукту: `?products=2` (id) и дополнительное задание `?products=помид` (часть названия или описания);
- пагинация списков: 10 записей на страницу, `?page=2`;
- админка `/admin/`, корень сайта перенаправляет на `/api/v1/`.

Примеры запросов — в [requests-examples.http](requests-examples.http).

## Локальный запуск

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # отредактируйте и загрузите: set -a; . ./.env; set +a
python manage.py migrate
python manage.py runserver
```

Нужна база PostgreSQL, параметры подключения — в `.env` (`DB_NAME`, `DB_USER`, `DB_PASSWORD`).

Тесты: `python manage.py test`.

## Деплой на VPS (REG.RU, Beget, Timeweb и др.)

Скрипт [deploy/setup.sh](deploy/setup.sh) разворачивает проект на чистом **Ubuntu 22.04 / 24.04**: ставит PostgreSQL, nginx, создаёт базу со случайным паролем, виртуальное окружение, systemd-сервис gunicorn и конфиг nginx.

1. Запушьте этот репозиторий на GitHub (публичный).
2. Закажите VPS с Ubuntu 24.04, хватит минимального тарифа (1 CPU, 1 ГБ RAM). Хостинг пришлёт IP и пароль root.
3. Подключитесь к серверу: `ssh root@<IP>` (в Windows — из PowerShell).
4. Выполните на сервере, подставив свой репозиторий:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/deploy/setup.sh -o setup.sh
   DJANGO_SUPERUSER_USERNAME=admin DJANGO_SUPERUSER_PASSWORD='придумайте-пароль' \
     bash setup.sh https://github.com/<you>/<repo>.git
   ```

   В конце скрипт напишет `Готово! Сайт работает: http://<IP>/api/v1/`.

5. Откройте `http://<IP>/` — это ссылка для сдачи задания.

Обновить сайт после новых коммитов — запустить ту же команду ещё раз: подтянется код, зависимости, миграции и статика. Пароль базы и `SECRET_KEY` сохраняются в `/etc/stocks_products.env`.

Если вы подключили домен, передайте его вторым аргументом: `bash setup.sh <repo> example.ru`.

### Как устроено на сервере

| Что | Где |
|---|---|
| код | `/srv/stocks_products/src` |
| виртуальное окружение | `/srv/stocks_products/venv` |
| настройки и секреты | `/etc/stocks_products.env` |
| статика (`collectstatic`) | `/var/www/stocks_products/static` |
| gunicorn | `systemctl status stocks_products`, сокет `/run/stocks_products/gunicorn.sock` |
| nginx | `/etc/nginx/sites-available/stocks_products` |

### Если что-то не работает

```bash
systemctl status stocks_products          # gunicorn запущен?
journalctl -u stocks_products -n 50       # ошибки Django/gunicorn
tail -n 50 /var/log/nginx/error.log       # ошибки nginx
```

Сайт не открывается снаружи, но `curl http://127.0.0.1/api/v1/` на сервере работает — проверьте, что в панели хостинга открыт порт 80.
