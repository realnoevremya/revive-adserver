# Revive Adserver v6.0.5 (Docker)

Сборка переделана по структуре официального docker-проекта (`codions/revive-adserver`), адаптирована под Revive `6.0.5` и ваш dev-поток.

## Запуск Dev

1. Запуск:
```bash
docker compose -p revive -f docker-compose.dev.yaml up --build
```

2. После старта установщик должен открыться по адресу:
`http://localhost:8082`

3. На шаге подключения к БД:
- Hostname: `mysql` <- имя контейнера
- Database Name: `revive`
- User: `revive`
- Password: `revive_pass`

4. Форма юзера произвольная:
- Administrator Username: `revive`
- Administrator Password: `1q2w3e4r5t6y7u8i9o`
- Administrator email: `revive@revive.ru`

4. Настройка кэша в админке:
- `memcachedServers`: `memcached:11211`
- `memcachedExpireTime`: оставить пустым (или задать число в секундах, больше `delivery.cacheExpire`)

5. Остановка:
```bash
docker compose -p revive -f docker-compose.dev.yaml down
```

6. Полный сброс (чистая установка):
```bash
$(ставь пробел впереди) docker compose -p revive -f docker-compose.dev.yaml down -v
```

## Запуск Prod

1. Проверь пароли БД в `docker-compose.yaml`:
- `MYSQL_ROOT_PASSWORD`
- `MYSQL_PASSWORD`

2. Запусти контейнеры:
```bash
docker compose -p revive -f docker-compose.yaml up -d --build
```

3. На шаге подключения к БД:
- Host: `mysql` <- имя сервиса БД в docker-compose сети
- Database: `revive`
- User: `root` или `revive`
- Password:
  - для `root`: значение `MYSQL_ROOT_PASSWORD`
  - для `revive`: значение `MYSQL_PASSWORD`

4. Настройка кэша в админке:
- `memcachedServers`: `memcached:11211`
- `memcachedExpireTime`: оставить пустым (или задать число в секундах, больше `delivery.cacheExpire`)

5. Остановка:
```bash
docker compose -p revive -f docker-compose.yaml down
```

6. Полный сброс (осторожно, удалит БД и файлы):
```bash
$(ставь пробел впереди) docker compose -p revive -f docker-compose.yaml down -v
```

## Обновление версии без потери БД и баннеров

Для upgrade добавлен скрипт [`scripts/upgrade.sh`](scripts/upgrade.sh).  

Он выполняет шаги автоматически:
- вызывает [`scripts/backup.sh`](scripts/backup.sh) автоматически перед апгрейдом (например: `backups/dev-v6.0.5-YYYYMMDD-HHMMSS`).
- бэкап БД (`mysqldump`)
- бэкап файлов `images`, `delivery`, `var`, `plugins`
- снимок предыдущей установки `app/previous-install.tar.gz` (для шага Configuration)
- скачивает архив целевой версии в `backups/.../archive`
- останавливает стек без удаления всех volume
- пересоздает `delivery` volume по умолчанию (и `plugins` volume опционально)
- пересборка на новой версии
- установка флага `var/UPGRADE`
- выводится готовый `previous path` для шага Configuration в мастере апгрейда.

### Бекап можно запустить вручную

```bash
scripts/backup.sh --mode prod

# or dev
scripts/backup.sh --mode dev
```

### Запуск апгрейда:

```bash
scripts/upgrade.sh --mode prod --version 6.0.6

# or dev
scripts/upgrade.sh --mode dev --version 6.0.6
```

### Важные параметры

- По умолчанию скрипт пересоздает только volume `delivery` (чтобы подтянуть свежие delivery-файлы из новой версии).
- Если нужно также пересоздать `plugins` (когда нет кастомных плагинов), добавь:

```bash
scripts/upgrade.sh --mode prod --version 6.0.6 --recreate-plugins
```

### Где брать архив новой версии

- Официальный архив:
  `https://download.revive-adserver.com/revive-adserver-v<VERSION>.tar.gz`
- Пример для `6.0.6`:
  `https://download.revive-adserver.com/revive-adserver-v6.0.6.tar.gz`
- В проекте это можно переопределить через `REVIVE_ARCHIVE_URL` или флаг скрипта `--archive-url`.
- При запуске `upgrade.sh` архив сохраняется в: `backups/.../archive/revive-adserver-v<VERSION>.tar.gz`.

### После выполнения скрипта

1. Открой `http://localhost:8082`
2. Пройди Upgrade Wizard до конца.
3. На шаге `Configuration`, в поле `Path to previous Revive Adserver installation` укажи путь из вывода `upgrade.sh`
   (обычно это `/tmp/revive-<текущая-версия>-prev` внутри контейнера `app`)
4. Проверь кампании, зоны, баннеры и выдачу на сайтах

### Откат из бэкапа

Быстрый способ (рекомендуется) — скрипт:

```bash
scripts/restore.sh --mode dev --backup-dir backups/dev-20260422-152427
# или для prod
scripts/restore.sh --mode prod --backup-dir backups/prod-YYYYMMDD-HHMMSS
```

Что делает `restore.sh`:
- восстанавливает БД и файлы `images/delivery/var/plugins`;
- если в `meta` бэкапа есть версия, пересобирает контейнер на этой версии;
- удаляет `var/UPGRADE`, чтобы админка не зависала на `install.php` после restore.

Официальный порядок обновления Revive (backup -> files upgrade -> DB upgrade wizard):
- https://www.revive-adserver.com/how-to/update/

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
