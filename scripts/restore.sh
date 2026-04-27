#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Восстановление Revive Adserver из бэкапа.

Пример:
  scripts/restore.sh --mode dev --backup-dir backups/dev-20260422-152427

Опции:
  --mode prod|dev              Режим стека (обязательно)
  --backup-dir PATH            Папка бэкапа (обязательно)
  -h, --help                   Показать справку
EOF
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Не найдена команда '$1'"
}

MODE=""
BACKUP_DIR=""
PROJECT_NAME="revive"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Неизвестный аргумент: $1"
            ;;
    esac
done

[[ -n "$MODE" ]] || die "Параметр --mode обязателен. Укажи: --mode dev или --mode prod"
[[ -n "$BACKUP_DIR" ]] || die "Параметр --backup-dir обязателен. Укажи путь к папке бэкапа"

case "$MODE" in
    prod)
        COMPOSE_FILE="docker-compose.yaml"
        APP_SERVICE="revive"
        ;;
    dev)
        COMPOSE_FILE="docker-compose.dev.yaml"
        APP_SERVICE="app"
        ;;
    *)
        die "Некорректный режим '$MODE'. Используй prod или dev."
        ;;
esac

[[ -f "$COMPOSE_FILE" ]] || die "Не найден файл '$COMPOSE_FILE'"
[[ -d "$BACKUP_DIR" ]] || die "Не найдена папка бэкапа '$BACKUP_DIR'"

require_cmd docker
require_cmd gunzip
require_cmd cat
require_cmd find

docker compose version >/dev/null 2>&1 || die "docker compose недоступен"
compose_cmd=(docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE")

sql_gz="$(find "$BACKUP_DIR/db" -maxdepth 1 -type f -name '*.sql.gz' | head -n1 || true)"
[[ -n "$sql_gz" ]] || die "В '$BACKUP_DIR/db' не найден SQL-дамп (*.sql.gz)"

images_tar="$BACKUP_DIR/app/images.tar.gz"
delivery_tar="$BACKUP_DIR/app/delivery.tar.gz"
var_tar="$BACKUP_DIR/app/var.tar.gz"
plugins_tar="$BACKUP_DIR/app/plugins.tar.gz"

[[ -f "$images_tar" ]] || die "Не найден файл '$images_tar'"
[[ -f "$delivery_tar" ]] || die "Не найден файл '$delivery_tar'"
[[ -f "$var_tar" ]] || die "Не найден файл '$var_tar'"
[[ -f "$plugins_tar" ]] || die "Не найден файл '$plugins_tar'"

db_name="$(basename "$sql_gz" .sql.gz)"
[[ -n "$db_name" ]] || die "Не удалось определить имя БД из '$sql_gz'"

log "Поднимаю необходимые сервисы..."
"${compose_cmd[@]}" up -d mysql "$APP_SERVICE"

running_services="$("${compose_cmd[@]}" ps --services --status running || true)"
echo "$running_services" | grep -qx "mysql" || die "Сервис 'mysql' не запущен"
echo "$running_services" | grep -qx "$APP_SERVICE" || die "Сервис '$APP_SERVICE' не запущен"

db_root_password="$("${compose_cmd[@]}" exec -T mysql sh -lc 'printf "%s" "${MYSQL_ROOT_PASSWORD:-}"')"

log "Восстанавливаю базу данных '${db_name}'..."
if [[ -n "$db_root_password" ]]; then
    "${compose_cmd[@]}" exec -T mysql sh -lc "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e \"DROP DATABASE IF EXISTS \`${db_name}\`; CREATE DATABASE \`${db_name}\`;\""
    gunzip -c "$sql_gz" | "${compose_cmd[@]}" exec -T mysql sh -lc "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" \"${db_name}\""
else
    "${compose_cmd[@]}" exec -T mysql mysql -uroot -e "DROP DATABASE IF EXISTS \`${db_name}\`; CREATE DATABASE \`${db_name}\`;"
    gunzip -c "$sql_gz" | "${compose_cmd[@]}" exec -T mysql mysql -uroot "$db_name"
fi

restore_tar() {
    local archive="$1"
    log "Восстанавливаю $(basename "$archive")..."
    cat "$archive" | "${compose_cmd[@]}" exec -T "$APP_SERVICE" sh -lc "tar -xzf - -C /"
}

restore_tar "$images_tar"
restore_tar "$delivery_tar"
restore_tar "$var_tar"
restore_tar "$plugins_tar"

log "Перезапускаю сервис приложения..."
"${compose_cmd[@]}" restart "$APP_SERVICE"

cat <<EOF

Восстановление завершено.
Бэкап: ${BACKUP_DIR}
Режим: ${MODE}
БД: ${db_name}

Проверь:
1) http://localhost:8082
2) вход в админку
3) кампании/зоны/баннеры

EOF
