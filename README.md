# Revive Adserver v6.0.5 (Docker)

Сборка переделана по структуре официального docker-проекта (`codions/revive-adserver`), адаптирована под Revive `6.0.5` и ваш dev-поток.

## Запуск Dev

1. Запуск:
```bash
docker compose -f docker-compose.dev.yaml up --build
```

2. После старта установщик должен открыться по адресу:
`http://localhost:8082`

3. На шаге подключения к БД:
- Host: `localhost`
- Database: `revive`
- User: `root` или `revive`
- Password:
  - для `root`: пустой
  - для `revive`: `revive_pass`

Важно:
- В dev `localhost` работает через общий MySQL socket между контейнерами.
- В dev `root` доступен без пароля.

4. Остановка:
```bash
docker compose -f docker-compose.dev.yaml down
```

5. Полный сброс (чистая установка):
```bash
docker compose -f docker-compose.dev.yaml down -v
```

## Запуск Prod

1. Проверь пароли БД в `/revive-adserver/docker-compose.yaml`:
- `MYSQL_ROOT_PASSWORD`
- `MYSQL_PASSWORD`

2. Запусти контейнеры:
```bash
docker compose -f docker-compose.yaml up -d --build
```

3. На шаге подключения к БД:
- Host: `localhost`
- Database: `revive`
- User: `root` или `revive`
- Password:
  - для `root`: значение `MYSQL_ROOT_PASSWORD`
  - для `revive`: значение `MYSQL_PASSWORD`

4. Остановка:
```bash
docker compose -f docker-compose.yaml down
```

5. Полный сброс (осторожно, удалит БД и файлы):
```bash
$(ставь пробел впереди) docker compose -p revive -f docker-compose.yaml down -v
```

Пример прокси в хостовом Nginx:

```nginx
server {
    listen 80;
    server_name ads.example.com;

    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
