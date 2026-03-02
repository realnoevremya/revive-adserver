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
- Host: `mysql`
- Database: `revive`
- User: `root` или `revive`
- Password:
  - для `root`: пустой
  - для `revive`: `revive_pass`

Важно:
- В dev `localhost` работает через общий MySQL socket между контейнерами.
- В dev `root` доступен без пароля.
- В dev memcached поднимается отдельным контейнером `memcached`.

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
- Host: `localhost`
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

Ниже сценарий для `prod` (`docker-compose.yaml`). Для `dev` логика та же, только используй `docker-compose.dev.yaml` и контейнеры `revive-adserver-dev-app` / `revive-adserver-dev-db`.

Что в этом проекте хранится в Docker volume и не пропадает при обычном перезапуске:
- БД MySQL: `mysql_data`
- Загруженные баннеры: `revive_images`
- Каталог доставки и delivery-файлы: `revive_delivery`
- Конфиг Revive и служебные данные: `revive_var`
- Каталог плагинов: `revive_plugins`

Важно:
- обычный `docker compose down` не удаляет эти данные
- `docker compose down -v` удаляет volume, а вместе с ними БД, баннеры и конфиг
- для обновления версию нужно менять без `-v`

Порядок обновления:

1. Сделай резервную копию БД:
```bash
mkdir -p backups
docker compose -p revive -f docker-compose.yaml exec -T mysql \
  mysqldump -uroot -p'ВАШ_MYSQL_ROOT_PASSWORD' --single-transaction --routines --triggers revive \
  > backups/revive-$(date +%F-%H%M).sql
```

2. Сделай резервную копию файлов, которые нельзя терять:
```bash
docker cp revive-adserver:/var/www/html/www/images ./backups/images-$(date +%F-%H%M)
docker cp revive-adserver:/var/www/html/www/delivery ./backups/delivery-$(date +%F-%H%M)
docker cp revive-adserver:/var/www/html/var ./backups/var-$(date +%F-%H%M)
docker cp revive-adserver:/var/www/html/plugins ./backups/plugins-$(date +%F-%H%M)
```

3. Поменяй версию Revive в трех местах:
- `docker/Dockerfile`
- `docker-compose.yaml`
- `docker-compose.dev.yaml`

Обновить нужно значение `REVIVE_VERSION`.

4. Останови контейнеры без удаления volume:
```bash
docker compose -p revive -f docker-compose.yaml down
```

5. Учти нюанс с `plugins` и `www/delivery`: оба каталога в текущей схеме лежат в отдельных volume, поэтому новая версия не обновит встроенные файлы автоматически, если оставить старые volume как есть.
- `delivery` лучше пересоздавать перед первым стартом новой версии, чтобы контейнер взял свежие файлы из нового образа
- если кастомных плагинов нет, volume с суффиксом `revive_plugins` тоже лучше пересоздать
- если кастомные плагины есть, сначала сохрани их отдельно, затем пересоздай volume и верни только свои кастомные каталоги, а не весь старый `plugins`

Пример:
```bash
docker volume ls
docker volume rm <имя_тома_с_revive_delivery>
docker volume rm <имя_тома_с_revive_plugins>
```

6. Собери и запусти новую версию:
```bash
docker compose -p revive -f docker-compose.yaml up -d --build
```

7. Открой `http://localhost:8082` и пройди мастер обновления.
- если Revive сразу показывает upgrade wizard, просто заверши обновление
- если открылся обычный логин, создай флаг обновления и обнови страницу:

```bash
docker compose -p revive -f docker-compose.yaml exec revive touch /var/www/html/var/UPGRADE
```

8. После завершения обновления проверь:
- вход в админку
- что кампании, зоны и баннеры на месте
- что баннеры отдаются на сайте

9. Если обновление пошло не так:
- останови контейнеры
- верни старый `REVIVE_VERSION`
- подними старую версию
- восстанови SQL-дамп и файлы из каталога `backups`

Этот порядок повторяет официальный подход Revive: сначала бэкап, затем обновление файлов, затем запуск мастера обновления БД:
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
