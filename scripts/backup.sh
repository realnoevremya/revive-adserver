#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Создание резервной копии Revive Adserver (Docker Compose).

Пример:
  scripts/backup.sh --mode dev

Опции:
  --mode prod|dev        Режим стека (обязательно)
  -h, --help             Показать справку

Что сохраняется:
1) SQL-дамп БД (mysqldump, gzip)
2) Каталоги приложения:
   - /var/www/html/www/images
   - /var/www/html/www/delivery
   - /var/www/html/var
   - /var/www/html/plugins
3) Метаданные:
   - docker-compose файл
   - docker/Dockerfile
   - список контейнеров compose
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
PROJECT_NAME="${BACKUP_PROJECT_NAME:-revive}"
OUTPUT_ROOT="${BACKUP_OUTPUT_ROOT:-./backups}"
BACKUP_LABEL="${BACKUP_LABEL:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
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

require_cmd docker
require_cmd tar
require_cmd gzip
require_cmd date

docker compose version >/dev/null 2>&1 || die "docker compose недоступен"
compose_cmd=(docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE")

log "Проверяю запущенные сервисы для режима '$MODE'..."
running_services="$("${compose_cmd[@]}" ps --services --status running || true)"
echo "$running_services" | grep -qx "$APP_SERVICE" || die "Сервис '$APP_SERVICE' не запущен"
echo "$running_services" | grep -qx "mysql" || die "Сервис 'mysql' не запущен"

timestamp="$(date +%Y%m%d-%H%M%S)"
if [[ -n "$BACKUP_LABEL" ]]; then
    safe_label="$(printf "%s" "$BACKUP_LABEL" | tr -cs '[:alnum:]_.-' '-')"
    BACKUP_DIR="${OUTPUT_ROOT}/${MODE}-${safe_label}-${timestamp}"
else
    BACKUP_DIR="${OUTPUT_ROOT}/${MODE}-${timestamp}"
fi
mkdir -p "$BACKUP_DIR/db" "$BACKUP_DIR/app" "$BACKUP_DIR/meta"

log "Сохраняю метаданные..."
cp "$COMPOSE_FILE" "$BACKUP_DIR/meta/"
if [[ -f "docker/Dockerfile" ]]; then
    cp "docker/Dockerfile" "$BACKUP_DIR/meta/"
fi
"${compose_cmd[@]}" ps > "$BACKUP_DIR/meta/compose-ps.txt"

db_name="$("${compose_cmd[@]}" exec -T mysql sh -lc 'printf "%s" "${MYSQL_DATABASE:-revive}"')"
db_root_password="$("${compose_cmd[@]}" exec -T mysql sh -lc 'printf "%s" "${MYSQL_ROOT_PASSWORD:-}"')"

sql_file="$BACKUP_DIR/db/${db_name}.sql"
log "Делаю дамп БД '${db_name}'..."
dump_cmd=("${compose_cmd[@]}" exec -T mysql mysqldump -uroot)
if [[ -n "$db_root_password" ]]; then
    dump_cmd+=("-p${db_root_password}")
fi
dump_cmd+=(--single-transaction --routines --triggers "$db_name")
"${dump_cmd[@]}" > "$sql_file"
gzip -f "$sql_file"

backup_path() {
    local src="$1"
    local out="$2"
    local normalized="${src#/}"

    log "Архивирую '${src}'..."
    "${compose_cmd[@]}" exec -T "$APP_SERVICE" sh -lc "test -e '${src}' && tar -C / -czf - '${normalized}'" > "$out"
}

backup_path "/var/www/html/www/images" "$BACKUP_DIR/app/images.tar.gz"
backup_path "/var/www/html/www/delivery" "$BACKUP_DIR/app/delivery.tar.gz"
backup_path "/var/www/html/var" "$BACKUP_DIR/app/var.tar.gz"
backup_path "/var/www/html/plugins" "$BACKUP_DIR/app/plugins.tar.gz"

log "Архивирую '/var/www/html' для шага 3 (Configuration)..."
"${compose_cmd[@]}" exec -T "$APP_SERVICE" sh -lc \
    "tar -C /var/www/html -czf - --exclude='./www/images' --exclude='./www/delivery' ." \
    > "$BACKUP_DIR/app/previous-install.tar.gz"

if command -v shasum >/dev/null 2>&1; then
    log "Считаю контрольные суммы..."
    (
        cd "$BACKUP_DIR"
        find . -type f ! -name 'SHA256SUMS.txt' -print0 | xargs -0 shasum -a 256 > SHA256SUMS.txt
    )
fi

cat <<EOF

Бэкап готов:
  ${BACKUP_DIR}

Файлы:
  - ${BACKUP_DIR}/db/${db_name}.sql.gz
  - ${BACKUP_DIR}/app/images.tar.gz
  - ${BACKUP_DIR}/app/delivery.tar.gz
  - ${BACKUP_DIR}/app/var.tar.gz
  - ${BACKUP_DIR}/app/plugins.tar.gz
  - ${BACKUP_DIR}/app/previous-install.tar.gz (для шага 3 Configuration)

Быстрый restore БД (пример):
  gunzip -c ${BACKUP_DIR}/db/${db_name}.sql.gz | docker compose -p ${PROJECT_NAME} -f ${COMPOSE_FILE} exec -T mysql mysql -uroot ${db_name}

EOF

echo "BACKUP_DIR=${BACKUP_DIR}"
