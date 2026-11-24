# Склады и товары

REST API на Django REST Framework: CRUD продуктов и складов, поиск, пагинация.

## Запуск

Установить зависимости:

```bash
pip install -r requirements.txt
```

Создать базу в PostgreSQL (параметры подключения задаются переменными окружения, см. `.env.example`) и прогнать миграции:

```bash
python manage.py migrate
```

Запустить сервер:

```bash
python manage.py runserver
```

Примеры запросов — в `requests-examples.http`.
