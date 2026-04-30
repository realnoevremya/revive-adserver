#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Пошаговый upgrade Revive Adserver с резервными копиями.

Пример:
  scripts/upgrade.sh --mode prod --version 6.0.6

Опции:
  --mode prod|dev              Режим стека (по умолчанию: prod)
  --version X.Y.Z              Целевая версия Revive (обязательно)
  --project NAME               docker compose project (по умолчанию: revive)
  --backup-root DIR            Корневая папка для бэкапов (по умолчанию: ./backups)
  --archive-url URL            Явный URL архива Revive (если не задан, берется официальный)
  --no-download                Не скачивать архив в локальный backup
  --no-recreate-delivery       Не пересоздавать volume с /www/delivery
  --recreate-plugins           Пересоздать volume с /plugins (по умолчанию не трогаем)
  --skip-build                 Не пересобирать образ (только up -d)
  -h, --help                   Показать справку

Что делает скрипт:
1) Бэкап БД (mysqldump), каталогов images/delivery/var/plugins и снимок previous-install
2) Опционально скачивает архив целевой версии в backups
3) Останавливает стек без удаления всех volume
4) Пересоздает delivery volume (по умолчанию) и plugins volume (опционально)
5) Поднимает стек с REVIVE_VERSION=<version>, ставит флаг var/UPGRADE и готовит previous path из локального бэкапа
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

check_db_connection_from_var_config() {
    local check_output

    log "🔎 Показываю активный DB-конфиг из var/default.conf.php..."

    if check_output="$("${compose_cmd[@]}" exec -T "$APP_SERVICE" sh -lc '
set -eu

default_conf="/var/www/html/var/default.conf.php"
[ -f "$default_conf" ] || {
  echo "NO_DEFAULT_CONF=$default_conf"
  exit 2
}

real_config="$(sed -n "s/^realConfig=//p" "$default_conf" | head -n1)"
real_config="${real_config#\"}"
real_config="${real_config%\"}"
[ -n "$real_config" ] || {
  echo "NO_REAL_CONFIG_IN_DEFAULT"
  exit 3
}

config_file="/var/www/html/var/${real_config}.conf.php"
[ -f "$config_file" ] || {
  echo "NO_REAL_CONFIG_FILE=$config_file"
  exit 4
}

current_host="$(sed -n "/^\[database\]/,/^\[/p" "$config_file" | sed "1d; \$d" | sed -n "s/^host=//p" | head -n1 | sed "s/^\"//; s/\"$//")"
case "$current_host" in
  localhost|localhost:3306|127.0.0.1|127.0.0.1:3306)
    sed -i "/^\[database\]/,/^\[/ s#^host=.*#host=\"mysql\"#" "$config_file"
    sed -i "/^\[database\]/,/^\[/ s#^port=.*#port=3306#" "$config_file"
    ;;
esac

echo "DEFAULT_CONF=$default_conf"
echo "REAL_CONFIG=$real_config"
echo "CONFIG_FILE=$config_file"
echo
echo "[database]"
sed -n "/^\[database\]/,/^\[/p" "$config_file" | sed "1d; \$d" | grep -E "^(host|port|username|name)=" || true
' 2>&1)"; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            log "ℹ️ ${line}"
        done <<< "$check_output"

        return 0
    fi

    log "⚠️ Не удалось прочитать активный DB-конфиг из var/default.conf.php"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        log "⚠️ ${line}"
    done <<< "$check_output"

    return 0
}

MODE="prod"
TARGET_VERSION=""
PROJECT_NAME="revive"
BACKUP_ROOT="./backups"
ARCHIVE_URL=""
DOWNLOAD_ARCHIVE=1
RECREATE_DELIVERY=1
RECREATE_PLUGINS=0
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --version)
            TARGET_VERSION="${2:-}"
            shift 2
            ;;
        --project)
            PROJECT_NAME="${2:-}"
            shift 2
            ;;
        --backup-root)
            BACKUP_ROOT="${2:-}"
            shift 2
            ;;
        --archive-url)
            ARCHIVE_URL="${2:-}"
            shift 2
            ;;
        --no-download)
            DOWNLOAD_ARCHIVE=0
            shift
            ;;
        --no-recreate-delivery)
            RECREATE_DELIVERY=0
            shift
            ;;
        --recreate-plugins)
            RECREATE_PLUGINS=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
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

[[ -n "$TARGET_VERSION" ]] || die "Укажи целевую версию: --version X.Y.Z"

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
require_cmd curl
require_cmd awk
require_cmd mktemp

docker compose version >/dev/null 2>&1 || die "docker compose недоступен"

compose_cmd=(docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE")

log "🚀 Запускаю upgrade: mode=${MODE}, target=${TARGET_VERSION}"
log "🔎 Определяю текущую установленную версию..."
CURRENT_VERSION="$("${compose_cmd[@]}" exec -T mysql sh -lc '
db="${MYSQL_DATABASE:-revive}"
query="SELECT value FROM rv_application_variable WHERE name='\''oa_version'\'' LIMIT 1;"
if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
    mysql -N -B -uroot -p"${MYSQL_ROOT_PASSWORD}" "$db" -e "$query" 2>/dev/null || true
else
    mysql -N -B -uroot "$db" -e "$query" 2>/dev/null || true
fi
')"
if [[ -z "$CURRENT_VERSION" ]]; then
    CURRENT_VERSION="unknown"
fi
log "🔎 Текущая версия: ${CURRENT_VERSION}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
backup_script="${script_dir}/backup.sh"
[[ -x "$backup_script" ]] || die "Не найден исполняемый backup-скрипт: ${backup_script}"

log "🗂️ Запускаю backup.sh перед апгрейдом..."
backup_log_file="$(mktemp "${TMPDIR:-/tmp}/revive-backup.XXXXXX")"
BACKUP_PROJECT_NAME="$PROJECT_NAME" \
BACKUP_OUTPUT_ROOT="$BACKUP_ROOT" \
BACKUP_LABEL="v${CURRENT_VERSION}" \
    "$backup_script" --mode "$MODE" | tee "$backup_log_file"

BACKUP_DIR="$(awk -F= '/^BACKUP_DIR=/{print $2}' "$backup_log_file" | tail -n1)"
rm -f "$backup_log_file"
[[ -n "$BACKUP_DIR" ]] || die "Не удалось определить путь к бэкапу из backup.sh"

mkdir -p "$BACKUP_DIR/archive"

APP_CONTAINER_ID="$("${compose_cmd[@]}" ps -q "$APP_SERVICE")"
[[ -n "$APP_CONTAINER_ID" ]] || die "Не удалось определить контейнер приложения"

if [[ "$DOWNLOAD_ARCHIVE" -eq 1 ]]; then
    archive_to_download="$ARCHIVE_URL"
    if [[ -z "$archive_to_download" ]]; then
        archive_to_download="https://download.revive-adserver.com/revive-adserver-v${TARGET_VERSION}.tar.gz"
    fi

    archive_file="$BACKUP_DIR/archive/revive-adserver-v${TARGET_VERSION}.tar.gz"
    log "📥 Скачиваю архив целевой версии ${TARGET_VERSION}..."
    log "📥 Источник: ${archive_to_download}"
    log "📥 Файл: ${archive_file}"
    if ! curl -fL --progress-bar "$archive_to_download" -o "$archive_file"; then
        fallback_url="https://codeload.github.com/revive-adserver/revive-adserver/tar.gz/refs/tags/v${TARGET_VERSION}"
        log "⚠️ Официальный архив недоступен, пробую fallback: ${fallback_url}"
        curl -fL --progress-bar "$fallback_url" -o "$archive_file"
        archive_to_download="$fallback_url"
    fi
    ARCHIVE_URL="$archive_to_download"
    log "✅ Архив сохранен: ${archive_file}"
fi

get_mount_volume_name() {
    local container_id="$1"
    local destination="$2"
    docker inspect "$container_id" --format "{{range .Mounts}}{{if eq .Destination \"$destination\"}}{{.Name}}{{end}}{{end}}"
}

delivery_volume="$(get_mount_volume_name "$APP_CONTAINER_ID" "/var/www/html/www/delivery")"
plugins_volume="$(get_mount_volume_name "$APP_CONTAINER_ID" "/var/www/html/plugins")"

volume_rm_if_exists() {
    local volume_name="$1"
    if [[ -z "$volume_name" ]]; then
        return
    fi
    if docker volume inspect "$volume_name" >/dev/null 2>&1; then
        log "Удаляю volume '${volume_name}'"
        docker volume rm "$volume_name" >/dev/null
    fi
}

log "🛑  Останавливаю стек без удаления всех volume..."
"${compose_cmd[@]}" down

if [[ "$RECREATE_DELIVERY" -eq 1 ]]; then
    log "🧹 Пересоздаю volume delivery..."
    volume_rm_if_exists "$delivery_volume"
fi

if [[ "$RECREATE_PLUGINS" -eq 1 ]]; then
    log "🧹 Пересоздаю volume plugins..."
    volume_rm_if_exists "$plugins_volume"
fi

up_env=("REVIVE_VERSION=${TARGET_VERSION}")
if [[ -n "$ARCHIVE_URL" ]]; then
    up_env+=("REVIVE_ARCHIVE_URL=${ARCHIVE_URL}")
fi

if [[ "$SKIP_BUILD" -eq 1 ]]; then
    log "▶️ Запускаю стек без пересборки..."
    env "${up_env[@]}" "${compose_cmd[@]}" up -d
else
    log "🏗️ Пересобираю образ и запускаю стек..."
    env "${up_env[@]}" "${compose_cmd[@]}" up -d --build
fi

log "🧷 Ставлю флаг обновления '/var/www/html/var/UPGRADE'..."
"${compose_cmd[@]}" exec -T "$APP_SERVICE" touch /var/www/html/var/UPGRADE || true

check_db_connection_from_var_config

PREVIOUS_PATH_HINT=""
previous_local_archive="$BACKUP_DIR/app/previous-install.tar.gz"
previous_path_version="$CURRENT_VERSION"
if [[ -z "$previous_path_version" || "$previous_path_version" == "unknown" ]]; then
    previous_path_version="from-backup"
fi
previous_path_in_container="/tmp/revive-${previous_path_version}-prev"

log "🧩 Готовлю previous path для шага 3 (Configuration)..."
if [[ -f "$previous_local_archive" ]]; then
    log "📦 Использую локальный снимок предыдущей установки:"
    log "📦 ${previous_local_archive}"
    APP_CONTAINER_ID_NEW="$("${compose_cmd[@]}" ps -q "$APP_SERVICE")"
    if [[ -n "$APP_CONTAINER_ID_NEW" ]]; then
        docker cp "$previous_local_archive" "${APP_CONTAINER_ID_NEW}:/tmp/revive-prev-source.tar.gz"
        "${compose_cmd[@]}" exec -T "$APP_SERVICE" sh -lc '
set -eu
PREV_PATH="'"$previous_path_in_container"'"
rm -rf "$PREV_PATH"
mkdir -p "$PREV_PATH"
tar -xzf /tmp/revive-prev-source.tar.gz -C "$PREV_PATH"
rm -f /tmp/revive-prev-source.tar.gz

merge_plugins_from_repo() {
  repo_root="$1"
  [ -d "$repo_root" ] || return 0

  mkdir -p "$PREV_PATH/plugins" "$PREV_PATH/plugins/etc" "$PREV_PATH/www/admin/plugins"
  for d in "$repo_root"/*; do
    [ -d "$d" ] || continue
    [ -d "$d/plugins" ] && cp -a "$d/plugins/." "$PREV_PATH/plugins/" || true
    [ -d "$d/www/admin/plugins" ] && cp -a "$d/www/admin/plugins/." "$PREV_PATH/www/admin/plugins/" || true
    name="${d##*/}"
    [ -f "$d/$name.xml" ] && cp -a "$d/$name.xml" "$PREV_PATH/plugins/etc/" || true
    [ -f "$d/$name.readme.txt" ] && cp -a "$d/$name.readme.txt" "$PREV_PATH/plugins/etc/" || true
  done
}

# Основной источник — снимок предыдущей установки.
merge_plugins_from_repo "$PREV_PATH/plugins_repo"
# Доп. fallback (локально из текущего контейнера), если в снимке нет plugins_repo.
merge_plugins_from_repo "/var/www/html/plugins_repo"
'
        PREVIOUS_PATH_HINT="$previous_path_in_container"
        log "✅ Previous path готов: ${PREVIOUS_PATH_HINT}"
    else
        log "⚠️ Не удалось найти app-контейнер для подготовки previous path."
    fi
else
    log "⚠️ В бэкапе не найден файл: ${previous_local_archive}"
    log "⚠️ previous path автоматически не подготовлен."
fi

if [[ -n "$PREVIOUS_PATH_HINT" ]]; then
    PREVIOUS_PATH_FOR_WIZARD="$PREVIOUS_PATH_HINT"
else
    PREVIOUS_PATH_FOR_WIZARD="(не подготовлен автоматически; проверь лог и содержимое ${previous_local_archive})"
fi

cat <<EOF

Готово. Бэкап лежит в:
  ${BACKUP_DIR}

Следующие шаги вручную:
1) Открой сайт
2) Пройди Upgrade Wizard до конца.
   На шаге Configuration в поле "Path to previous Revive Adserver installation" укажи:
   ${PREVIOUS_PATH_FOR_WIZARD}
3) Проверь кампании/зоны/баннеры и отдачу креативов

Если нужно откатиться:
  scripts/restore.sh --mode ${MODE} --backup-dir ${BACKUP_DIR}

EOF
