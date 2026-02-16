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
- Host: `localhost` (можно оставить по умолчанию) или `mysql`
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
