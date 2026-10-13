#!/usr/bin/env bash
set -Eeuo pipefail

GITHUB_USER="Nikita67767"
REPO_NAME="3x-ui-material-theme"
BRANCH="main"

THEME_DIR="/etc/3x-ui/sub_templates/my-theme"
INDEX_FILE="$THEME_DIR/index.html"
RAW_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH/index.html"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Запусти от root."
command -v curl >/dev/null || die "Не найден curl."
command -v python3 >/dev/null || die "Не найден python3."

TMP="$(mktemp)"
STOPPED=0

cleanup() {
    rm -f "$TMP"
    if [[ "$STOPPED" == 1 ]]; then
        systemctl start x-ui || true
    fi
}
trap cleanup EXIT

echo "=========================================="
echo " Material You Theme — 3x-ui 3.8.5"
echo "=========================================="

info "Скачиваем шаблон..."
curl -fsSL --connect-timeout 15 --max-time 120 \
    "$RAW_URL" -o "$TMP" ||
    die "Не удалось скачать шаблон."

[[ -s "$TMP" ]] || die "Скачанный файл пустой."

grep -qiE '<!doctype[[:space:]]+html|<html([[:space:]>])' "$TMP" ||
    die "Скачанный файл не похож на HTML."

install -d -m 755 "$THEME_DIR"

if [[ -f "$INDEX_FILE" ]]; then
    cp -p "$INDEX_FILE" "$INDEX_FILE.bak"
    info "Создана резервная копия шаблона."
fi

install -m 644 "$TMP" "$INDEX_FILE"
ok "Шаблон установлен: $INDEX_FILE"

info "Ищем базу данных..."

DB_FILE=""
for p in \
    /etc/x-ui/x-ui.db \
    /usr/local/x-ui/db/x-ui.db \
    /usr/local/x-ui/x-ui.db \
    /etc/3x-ui/x-ui.db
do
    if [[ -f "$p" ]]; then
        DB_FILE="$p"
        break
    fi
done

if [[ -z "$DB_FILE" ]]; then
    DB_FILE="$(find /etc /usr/local -type f -name x-ui.db \
        -print -quit 2>/dev/null || true)"
fi

[[ -n "$DB_FILE" && -f "$DB_FILE" ]] ||
    die "База x-ui.db не найдена. Файл темы установлен, но не активирован."

info "База: $DB_FILE"

systemctl is-active --quiet x-ui ||
    warn "Служба x-ui уже остановлена или не запущена."

# Останавливаем панель перед изменением SQLite.
if systemctl is-active --quiet x-ui; then
    systemctl stop x-ui
    STOPPED=1
fi

# Резервная копия базы.
DB_BACKUP="${DB_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
cp -a "$DB_FILE" "$DB_BACKUP"
ok "Резервная копия базы: $DB_BACKUP"

info "Активируем каталог темы в настройках..."

if ! DB_FILE="$DB_FILE" THEME_DIR="$THEME_DIR" python3 <<'PY'
import os
import sqlite3
import sys

db_path = os.environ["DB_FILE"]
theme_dir = os.environ["THEME_DIR"].rstrip("/") + "/"

conn = sqlite3.connect(db_path, timeout=15)

try:
    cur = conn.cursor()

    tables = {
        row[0] for row in cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )
    }

    if "settings" not in tables:
        raise RuntimeError("В базе не найдена таблица settings")

    columns = {
        row[1] for row in cur.execute("PRAGMA table_info(settings)")
    }

    if not {"key", "value"}.issubset(columns):
        raise RuntimeError(
            "Неизвестная структура таблицы settings; база не изменена"
        )

    row = cur.execute(
        "SELECT value FROM settings WHERE key = ?",
        ("subThemeDir",)
    ).fetchone()

    if row is None:
        raise RuntimeError(
            "Ключ subThemeDir отсутствует. "
            "Автоматическая запись отменена для безопасности."
        )

    cur.execute(
        "UPDATE settings SET value = ? WHERE key = ?",
        (theme_dir, "subThemeDir")
    )

    conn.commit()

    saved = cur.execute(
        "SELECT value FROM settings WHERE key = ?",
        ("subThemeDir",)
    ).fetchone()

    if not saved or saved[0].rstrip("/") != theme_dir.rstrip("/"):
        raise RuntimeError("Не удалось проверить сохранённое значение")

    print("Настройка subThemeDir =", saved[0])

except Exception:
    conn.rollback()
    raise
finally:
    conn.close()
PY
then
    die "Не удалось автоматически активировать тему. Резервная копия сохранена."
fi

info "Запускаем панель..."
systemctl start x-ui
STOPPED=0

sleep 2

if systemctl is-active --quiet x-ui; then
    ok "Служба x-ui запущена."
else
    warn "Проверь состояние службы: systemctl status x-ui"
    exit 1
fi

echo
ok "Установка завершена."
echo "Каталог темы: $THEME_DIR/"
echo "Настройка БД: subThemeDir"
echo "Проверь страницу подписки в браузере."
