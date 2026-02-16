# Revive Adserver v6.0.5 (Dev)

Сборка переделана по структуре официального docker-проекта (`codions/revive-adserver`), адаптирована под Revive `6.0.5` и ваш dev-поток.

## Запуск Dev

1. Запуск:
```bash
docker compose -f docker-compose.dev.yaml up --build
```

2. После старта установщик должен открыться по адресу:
`http://localhost:8082`

3. На шаге подключения к БД:
- Host: `mysql`
- Database: `revive_605`
- User: `root` (рекомендуется) или `revive`
- Password: пустой

Важно:
- Не используйте `localhost` как Host, иначе будет ошибка `No such file or directory (2002)`.
- В dev для пользователей `root` и `revive` принудительно выставляется пустой пароль.

4. Остановка:
```bash
docker compose -f docker-compose.dev.yaml down
```

5. Полный сброс (чистая установка):
```bash
docker compose -f docker-compose.dev.yaml down -v
```
