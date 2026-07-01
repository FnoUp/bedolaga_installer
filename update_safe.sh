#!/bin/bash
# ==============================================================================
# update_safe.sh — БЕЗОПАСНОЕ обновление Bedolaga, устойчивое к апдейтам upstream
#
# Идея: ваша фича живёт в форке. Обновления автора (upstream) вливаются через
# git merge. Если конфликт — обновление ОТМЕНЯЕТСЯ, прод продолжает работать на
# текущей версии (ничего не ломается). Если merge чистый — пересборка + проверка;
# при сбое — АВТО-ОТКАТ на предыдущую рабочую версию.
#
# Запуск:   bash update_safe.sh
#   --check        только проверить, есть ли апдейты upstream (без изменений)
#   --no-upstream  обновиться только до свежего форка (без merge upstream)
# ==============================================================================
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/bedolaga}"
FORK_URL="${FORK_URL:-https://github.com/FnoUp/remnawave-bedolaga-telegram-bot.git}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git}"
BRANCH="${BRANCH:-main}"
MODE="${1:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

[[ $EUID -ne 0 ]] && { err "Запустите от root"; exit 1; }
[[ ! -d "$INSTALL_DIR/.git" ]] && { err "$INSTALL_DIR — не git-репозиторий"; exit 1; }
cd "$INSTALL_DIR"

_get() { grep -m1 "^${1}=" "$INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d "\"' " || true; }
notify() {
    local token chat topic; token=$(_get BOT_TOKEN); chat=$(_get ADMIN_NOTIFICATIONS_CHAT_ID); topic=$(_get ADMIN_NOTIFICATIONS_INFRASTRUCTURE_TOPIC_ID)
    [[ -z "$token" || -z "$chat" ]] && return 0
    BOT_TOKEN="$token" CHAT="$chat" TOPIC="$topic" TEXT="$1" python3 - <<'PY' 2>/dev/null || true
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

# Гарантируем наличие remotes
git remote get-url origin   >/dev/null 2>&1 && git remote set-url origin "$FORK_URL"   || git remote add origin "$FORK_URL"
git remote get-url upstream >/dev/null 2>&1 && git remote set-url upstream "$UPSTREAM_URL" || git remote add upstream "$UPSTREAM_URL"

log "Получаю изменения (origin + upstream)..."
git fetch origin --tags --prune 2>&1 | tail -1
git fetch upstream --prune 2>&1 | tail -1

CURRENT=$(git rev-parse HEAD)
UPSTREAM_HEAD=$(git rev-parse "upstream/$BRANCH" 2>/dev/null || echo "")
BEHIND=$(git rev-list --count "HEAD..upstream/$BRANCH" 2>/dev/null || echo "0")

# ── Режим проверки ────────────────────────────────────────────────────────────
if [[ "$MODE" == "--check" ]]; then
    if [[ "$BEHIND" == "0" ]]; then ok "Обновлений upstream нет. Версия актуальна (${CURRENT:0:8})";
    else warn "Доступно обновлений upstream: $BEHIND коммит(ов)"; fi
    exit 0
fi

# ── 1. Бэкап (DB + .env + текущий коммит) ─────────────────────────────────────
STAMP=$(date +%F-%H%M%S)
log "Бэкап перед обновлением..."
cp "$INSTALL_DIR/.env" "$INSTALL_DIR/.env.bak.$STAMP" 2>/dev/null || true
echo "$CURRENT" > "$INSTALL_DIR/.last_good_commit"
CUR_IMAGE=$(docker images -q bedolaga-bot 2>/dev/null | head -1 || true)
[[ -n "$CUR_IMAGE" ]] && docker tag "$CUR_IMAGE" bedolaga-bot:rollback-$STAMP 2>/dev/null && ok "Образ сохранён: bedolaga-bot:rollback-$STAMP"
if docker ps --format '{{.Names}}' | grep -q '^remnawave_bot_db$'; then
    docker exec remnawave_bot_db pg_dump -U remnawave_user remnawave_bot 2>/dev/null \
        | gzip > "$INSTALL_DIR/db_backup_$STAMP.sql.gz" && ok "Дамп БД: db_backup_$STAMP.sql.gz" || warn "Дамп БД пропущен"
fi

# ── 2. Обновление кода ────────────────────────────────────────────────────────
if [[ "$MODE" == "--no-upstream" ]]; then
    log "Обновляюсь до свежего форка (origin/$BRANCH)..."
    if ! git merge --no-edit "origin/$BRANCH" 2>&1 | tail -3; then
        git merge --abort 2>/dev/null || true
        err "Конфликт с форком — обновление отменено, прод не тронут"
        notify "⚠️ <b>Bedolaga: обновление отменено</b>%0AКонфликт при слиянии форка. Текущая версия работает.%0A%0A<i>#update #bedolaga</i>"
        exit 1
    fi
else
    if [[ "$BEHIND" == "0" ]]; then
        ok "Upstream без изменений — обновлять нечего"
        notify "ℹ️ <b>Bedolaga: обновлений нет</b>%0AВерсия актуальна (${CURRENT:0:8})%0A%0A<i>#update #bedolaga</i>"
        exit 0
    fi
    log "Вливаю upstream/$BRANCH (merge)..."
    if ! git merge --no-edit "upstream/$BRANCH" 2>&1 | tail -5; then
        warn "КОНФЛИКТ слияния — обновление отменяется, прод остаётся на рабочей версии"
        git merge --abort 2>/dev/null || true
        notify "🛑 <b>Bedolaga: обновление отложено</b>%0AКонфликт с обновлением автора — нужен ручной merge форка.%0AПрод работает на ${CURRENT:0:8}.%0A%0A<i>#update #conflict #bedolaga</i>"
        err "Разрешите конфликт в форке вручную (git merge upstream/main), затем запустите update_safe.sh --no-upstream"
        exit 1
    fi
    ok "Merge upstream выполнен чисто"
fi

# ── 3. Пересборка + запуск ────────────────────────────────────────────────────
log "Пересборка образа..."
docker compose build bot 2>&1 | tail -2
log "Запуск..."
docker compose up -d bot 2>&1 | tail -1

# ── 4. Health-check ───────────────────────────────────────────────────────────
log "Проверка работоспособности (до 90 сек)..."
HEALTHY=false
for i in $(seq 1 18); do
    sleep 5
    state=$(docker compose ps bot --format '{{.State}}' 2>/dev/null || true)
    if [[ "$state" == "running" ]]; then
        if ! docker compose logs --tail=50 bot 2>&1 | grep -qiE 'Traceback|CRITICAL|Migration failed|Миграция.*ошибк'; then
            HEALTHY=true; break
        fi
    fi
done

# ── 5. Итог / авто-откат ──────────────────────────────────────────────────────
if $HEALTHY; then
    NEW=$(git rev-parse HEAD)
    ok "Обновление успешно (${NEW:0:8})"
    # Сохраняем результат в форк, чтобы deploy_stable видел свежий main
    git push origin "$BRANCH" 2>&1 | tail -1 || warn "Не удалось запушить в форк (запушьте вручную)"
    notify "✅ <b>Bedolaga: обновление успешно</b>%0AВерсия: ${NEW:0:8}%0AВлито коммитов upstream: $BEHIND%0A%0A<i>#update #bedolaga</i>"
    docker compose ps bot
else
    err "Бот не поднялся — АВТО-ОТКАТ на ${CURRENT:0:8}"
    git reset --hard "$CURRENT" 2>&1 | tail -1
    if docker image inspect bedolaga-bot:rollback-$STAMP >/dev/null 2>&1; then
        docker tag bedolaga-bot:rollback-$STAMP bedolaga-bot:latest 2>/dev/null || true
    fi
    docker compose build bot 2>&1 | tail -1
    docker compose up -d bot 2>&1 | tail -1
    notify "🛑 <b>Bedolaga: АВТО-ОТКАТ</b>%0AОбновление сломало бота — вернулись на ${CURRENT:0:8}.%0AБэкап БД: db_backup_$STAMP.sql.gz%0A%0A<i>#update #rollback #bedolaga</i>"
    err "Откат выполнен. Разберите ошибку: docker compose logs --tail=80 bot"
    exit 1
fi

echo ""
ok "Готово. Бэкапы: .env.bak.$STAMP, db_backup_$STAMP.sql.gz, образ bedolaga-bot:rollback-$STAMP"
echo -e "  Ручной откат: ${CYAN}cd $INSTALL_DIR && git reset --hard $CURRENT && docker compose build bot && docker compose up -d bot${NC}"
