#!/usr/bin/env bash

set -e

# Настройки под твой репозиторий
GITHUB_USER="Nikita67767"
REPO_NAME="3x-ui-material-theme"
BRANCH="main"

RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/index.html"
THEME_DIR="/etc/3x-ui/sub_templates/my-theme"
INDEX_FILE="${THEME_DIR}/index.html"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}==================================================${NC}"
echo -e "${CYAN}   Установка Material You темы для 3x-ui          ${NC}"
echo -e "${CYAN}==================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Запустите скрипт с правами root: sudo bash <(...) ${NC}"
  exit 1
fi

echo -e "\n${YELLOW}[1/4]${NC} Создаём директорию темы..."
mkdir -p "$THEME_DIR"

echo -e "${YELLOW}[2/4]${NC} Скачиваем шаблон с GitHub..."
if ! curl -sSLf "$RAW_URL" -o "$INDEX_FILE"; then
  echo -e "${RED}[!] Не удалось скачать шаблон. Проверьте подключение или наличие файла в ветке main.${NC}"
  exit 1
fi
chmod 644 "$INDEX_FILE"

echo -e "${YELLOW}[3/4]${NC} Поиск базы данных 3x-ui..."
DB_FILE=""
for p in "/etc/x-ui/x-ui.db" "/usr/local/x-ui/db/x-ui.db" "/usr/local/x-ui/x-ui.db"; do
  if [ -f "$p" ]; then
    DB_FILE="$p"
    break
  fi
done

if [ -z "$DB_FILE" ]; then
  DB_FILE=$(find /etc /usr/local -name "x-ui.db" 2>/dev/null | head -n 1 || true)
fi

echo -e "${YELLOW}[4/4]${NC} Активация темы в настройках..."
if [ -n "$DB_FILE" ] && command -v python3 &>/dev/null; then
  systemctl stop x-ui 2>/dev/null || true

  python3 - << PYEOF
import sqlite3

db_path = "$DB_FILE"
target_val = "$THEME_DIR/"

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("SELECT key FROM settings WHERE key='subThemePath'")
if cur.fetchone():
    cur.execute("UPDATE settings SET value=? WHERE key='subThemePath'", (target_val,))
else:
    cur.execute("INSERT INTO settings (key, value) VALUES ('subThemePath', ?)", (target_val,))

conn.commit()
conn.close()
PYEOF

  systemctl start x-ui 2>/dev/null || true
  APPLIED_AUTO=true
else
  systemctl restart x-ui 2>/dev/null || true
  APPLIED_AUTO=false
fi

echo -e "\n${GREEN}✔ Установка завершена успешно!${NC}"
echo -e "${CYAN}--------------------------------------------------${NC}"
if [ "$APPLIED_AUTO" = true ]; then
  echo -e "${GREEN}Тема активирована в панели 3x-ui автоматически!${NC}"
  echo -e "Открывайте ссылку подписки клиента в браузере."
else
  echo -e "Файл скачан. Для ручной активации в веб-панели:"
  echo -e "Настройки панели → Подписка → Профиль"
  echo -e "В поле «Каталог темы подписки» укажите: ${YELLOW}$THEME_DIR/${NC}"
fi
echo -e "${CYAN}--------------------------------------------------${NC}"
