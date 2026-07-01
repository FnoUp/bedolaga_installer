#!/bin/bash
# ==============================================================================
# deploy_stable.sh — СТАБИЛЬНОЕ развёртывание Bedolaga из вашего форка
#
# Разворачивает бот, ЗАФИКСИРОВАННЫЙ на конкретной проверенной версии (тег/коммит).
# Не зависит от upstream — версия не «уедет» сама. Идеально для прод-сервера.
#
# Запуск:   bash deploy_stable.sh
# Сменить версию:  PINNED_REF=stable-support-payment-v2 bash deploy_stable.sh
# ==============================================================================
set -euo pipefail

# ── Настройки ─────────────────────────────────────────────────────────────────
INSTALL_DIR="${INSTALL_DIR:-/opt/bedolaga}"
FORK_URL="${FORK_URL:-https://github.com/FnoUp/remnawave-bedolaga-telegram-bot.git}"
# Зафиксированная версия (тег или commit SHA). НЕ обновляется автоматически.
PINNED_REF="${PINNED_REF:-stable-support-payment-v1}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

[[ $EUID -ne 0 ]] && { err "Запустите от root"; exit 1; }
[[ ! -d "$INSTALL_DIR" ]] && { err "$INSTALL_DIR не найден. Сначала установите бота (install_bedolaga.sh)"; exit 1; }

cd "$INSTALL_DIR"

# ── Telegram-уведомление (best-effort) ────────────────────────────────────────
_get() { grep -m1 "^${1}=" "$INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d "\"' " || true; }
notify() {
    local text="$1"
    local token chat topic
    token=$(_get BOT_TOKEN); chat=$(_get ADMIN_NOTIFICATIONS_CHAT_ID); topic=$(_get ADMIN_NOTIFICATIONS_INFRASTRUCTURE_TOPIC_ID)
    [[ -z "$token" || -z "$chat" ]] && return 0
    BOT_TOKEN="$token" CHAT="$chat" TOPIC="$topic" TEXT="$text" python3 - <<'PY' 2>/dev/null || true
import os, json, urllib.request
p={"chat_id":os.environ["CHAT"],"text":os.environ["TEXT"],"parse_mode":"HTML"}
t=os.environ.get("TOPIC")
if t:
    try: p["message_thread_id"]=int(t)
    except ValueError: pass
try:
    urllib.request.urlopen(urllib.request.Request(
        f'https://api.telegram.org/bot{os.environ["BOT_TOKEN"]}/sendMessage',
        data=json.dumps(p).encode(), headers={"Content-Type":"application/json"}), timeout=10)
except Exception: pass
PY
}

# ── 1. Бэкап перед изменениями ────────────────────────────────────────────────
STAMP=$(date +%F-%H%M%S)
log "Бэкап .env и текущего состояния..."
cp "$INSTALL_DIR/.env" "$INSTALL_DIR/.env.bak.$STAMP" 2>/dev/null || true
PREV_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
echo "$PREV_COMMIT" > "$INSTALL_DIR/.last_stable_commit"
ok "Текущий коммит сохранён: ${PREV_COMMIT:0:8}"

# Дамп БД (если контейнер БД жив)
if docker ps --format '{{.Names}}' | grep -q '^remnawave_bot_db$'; then
    log "Дамп базы данных..."
    docker exec remnawave_bot_db pg_dump -U remnawave_user remnawave_bot 2>/dev/null \
        | gzip > "$INSTALL_DIR/db_backup_$STAMP.sql.gz" && ok "Дамп БД: db_backup_$STAMP.sql.gz" || warn "Дамп БД пропущен"
fi

# ── 2. Переключение на форк и фиксацию версии ────────────────────────────────
log "Переключаю origin на форк: $FORK_URL"
git remote set-url origin "$FORK_URL"
log "Получаю версию: $PINNED_REF"
git fetch origin --tags --prune 2>&1 | tail -1

# Проверяем что ref существует
if ! git rev-parse --verify "origin/$PINNED_REF^{commit}" >/dev/null 2>&1 \
   && ! git rev-parse --verify "$PINNED_REF^{commit}" >/dev/null 2>&1; then
    err "Версия '$PINNED_REF' не найдена в форке. Проверьте тег/коммит."
    exit 1
fi

log "Фиксирую рабочую копию на $PINNED_REF (git reset --hard)"
git reset --hard "$PINNED_REF" 2>&1 | tail -1
NEW_COMMIT=$(git rev-parse HEAD)
ok "Версия зафиксирована: ${NEW_COMMIT:0:8}"

# ── 3. Сборка и запуск ────────────────────────────────────────────────────────
log "Сборка образа (2–5 мин)..."
docker compose build bot 2>&1 | tail -2
log "Запуск..."
docker compose up -d bot 2>&1 | tail -1

# ── 4. Health-check ───────────────────────────────────────────────────────────
log "Проверка состояния (до 90 сек)..."
HEALTHY=false
for i in $(seq 1 18); do
    sleep 5
    state=$(docker compose ps bot --format '{{.State}}' 2>/dev/null || true)
    if [[ "$state" == "running" ]]; then
        # Бот стартовал и нет фатальных ошибок миграции
        if ! docker compose logs --tail=40 bot 2>&1 | grep -qiE 'Traceback|CRITICAL|Migration failed|Миграция.*ошибк'; then
            HEALTHY=true; break
        fi
    fi
done

if $HEALTHY; then
    ok "Бот запущен и работает (версия ${NEW_COMMIT:0:8})"
    notify "✅ <b>Bedolaga: стабильный деплой</b>%0AВерсия: <code>$PINNED_REF</code> (${NEW_COMMIT:0:8})%0A%0A<i>#deploy #bedolaga</i>"
    docker compose ps bot
else
    err "Бот не поднялся корректно — выполняю откат на ${PREV_COMMIT:0:8}"
    git reset --hard "$PREV_COMMIT" 2>&1 | tail -1
    docker compose build bot 2>&1 | tail -1
    docker compose up -d bot 2>&1 | tail -1
    notify "⚠️ <b>Bedolaga: деплой откатан</b>%0AНовая версия не поднялась, вернулись на ${PREV_COMMIT:0:8}%0A%0A<i>#deploy #rollback #bedolaga</i>"
    err "Откат выполнен. Логи: docker compose logs --tail=50 bot"
    exit 1
fi

echo ""
ok "Готово. Откат вручную: cd $INSTALL_DIR && git reset --hard $PREV_COMMIT && docker compose build bot && docker compose up -d bot"
