#!/bin/bash
# ==============================================================
# install_bedolaga.sh — автоустановщик Bedolaga Telegram-бота
# Устанавливается на тот же сервер что и Remnawave Panel
# Репо: https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot
# ==============================================================
set -euo pipefail
cd /  # фиксируем CWD до любых операций с директориями

INSTALL_DIR="/opt/bedolaga"
REPO_URL="https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git"
REMNAWAVE_DIR="/opt/remnawave"
REMNAWAVE_NETWORK="remnawave-network"
SELF_PATH="/usr/local/bin/bedolaga"
SCRIPT_URL="https://raw.githubusercontent.com/FnoUp/bedolaga_installer/main/install_bedolaga.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}"; }
log_ok()    { echo -e "${GREEN}[✓]${NC} $*"; }

set_env() {
    local key=$1 value=$2 file=$3
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

ask() {
    local _var=$1 _msg=$2 _default=${3:-}
    local _value
    while true; do
        if [[ -n "$_default" ]]; then
            read -rp $'\e[0;36m?\e[0m '"$_msg [$_default]: " _value
            _value="${_value:-$_default}"
        else
            read -rp $'\e[0;36m?\e[0m '"$_msg: " _value
        fi
        [[ -n "$_value" ]] && { printf -v "$_var" '%s' "$_value"; return; }
        log_error "Обязательное поле"
    done
}

ask_secret() {
    local _var=$1 _msg=$2
    local _value
    while true; do
        read -srp $'\e[0;36m?\e[0m '"$_msg: " _value; echo
        [[ -n "$_value" ]] && { printf -v "$_var" '%s' "$_value"; return; }
        log_error "Обязательное поле"
    done
}

# ── Флаги состояния ───────────────────────────────────────────
INSTALL_OK=false
RW_ENV_BACKUP=""

# ── Очистка при прерывании или ошибке ─────────────────────────
cleanup() {
    [[ "$INSTALL_OK" == "true" ]] && return
    set +e

    echo ""
    log_warn "Установка не завершена. Удаляю незавершённые файлы..."

    if [[ -d "$INSTALL_DIR" ]]; then
        cd "$INSTALL_DIR" 2>/dev/null && docker compose down --volumes 2>/dev/null || true
        cd / && rm -rf "$INSTALL_DIR"
        log_info "Удалено: $INSTALL_DIR"
    fi

    if [[ -n "$RW_ENV_BACKUP" ]] && [[ -f "$RW_ENV_BACKUP" ]]; then
        cp "$RW_ENV_BACKUP" "${REMNAWAVE_DIR}/.env"
        cd "$REMNAWAVE_DIR" 2>/dev/null && docker compose restart remnawave 2>/dev/null || true
        log_info "Восстановлен: ${REMNAWAVE_DIR}/.env"
    fi

    echo ""
    log_warn "Повторите установку командой: ${BOLD}bedolaga${NC}"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

# ── Баннер ────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════════════════════╗"
echo -e "║   Bedolaga Auto-Installer                       ║"
echo -e "║   Telegram VPN-бот для Remnawave                ║"
echo -e "╚══════════════════════════════════════════════════╝${NC}\n"

# ── ШАГ 1: Проверки ───────────────────────────────────────────
log_step "ШАГ 1: Проверка окружения"

[[ $EUID -ne 0 ]] && { log_error "Запустите от root: sudo bash install_bedolaga.sh"; exit 1; }
log_ok "Root"

# Самоустановка как системная команда (работает при запуске через curl pipe)
if [[ "$(realpath "$0" 2>/dev/null || echo "$0")" != "$SELF_PATH" ]]; then
    if curl -fsSL "$SCRIPT_URL" -o "$SELF_PATH" 2>/dev/null && chmod +x "$SELF_PATH"; then
        log_ok "Команда 'bedolaga' установлена → при прерывании просто запустите: bedolaga"
    fi
fi

if ! command -v docker &>/dev/null; then
    log_info "Устанавливаю Docker..."
    curl -fsSL https://get.docker.com | sh
fi
log_ok "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

docker compose version &>/dev/null || { log_error "Нужен docker compose v2 (Docker >= 20.10)"; exit 1; }
log_ok "Docker Compose v2"

if ! command -v git &>/dev/null; then
    log_info "Устанавливаю Git..."
    apt-get install -y -q git
fi
log_ok "Git"

command -v openssl &>/dev/null || apt-get install -y -q openssl

# ── ШАГ 2: Проверка Remnawave ─────────────────────────────────
log_step "ШАГ 2: Проверка Remnawave Panel"

[[ ! -d "$REMNAWAVE_DIR" ]] && {
    log_error "Директория $REMNAWAVE_DIR не найдена. Сначала установите Remnawave Panel."
    exit 1
}
docker network ls --format '{{.Name}}' | grep -q "^${REMNAWAVE_NETWORK}$" || {
    log_error "Docker-сеть '$REMNAWAVE_NETWORK' не найдена. Убедитесь что Remnawave запущена."
    exit 1
}
log_ok "Remnawave найдена, сеть $REMNAWAVE_NETWORK существует"

# ── ШАГ 3: Проверка существующих файлов ──────────────────────
log_step "ШАГ 3: Проверка существующей установки"

if [[ -d "$INSTALL_DIR" ]]; then
    # Проверяем запущен ли контейнер бота
    BOT_RUNNING=false
    if cd "$INSTALL_DIR" 2>/dev/null && \
       docker compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | grep -q "^bot.*running"; then
        BOT_RUNNING=true
    fi
    cd /

    if $BOT_RUNNING; then
        log_warn "Bedolaga уже установлена и запущена"
        read -rp $'\e[1;33m?\e[0m Обновить (git pull + rebuild)? [да/нет]: ' _ans
        if [[ "$_ans" =~ ^(да|yes|y|д)$ ]]; then
            [[ -f "$INSTALL_DIR/.env" ]] && cp "$INSTALL_DIR/.env" "$INSTALL_DIR/.env.bak.$(date +%F-%H%M%S)"
            cd "$INSTALL_DIR"
            git pull origin main
            docker compose build --pull
            docker compose up -d
            INSTALL_OK=true
            log_ok "Обновлено"
            docker compose ps
            exit 0
        else
            INSTALL_OK=true
            exit 0
        fi
    else
        log_warn "Найдена незавершённая или остановленная установка в $INSTALL_DIR"
        log_info "Удаляю старые файлы..."
        cd "$INSTALL_DIR" 2>/dev/null && docker compose down --volumes 2>/dev/null || true
        cd / && rm -rf "$INSTALL_DIR"
        log_ok "Очищено. Продолжаю свежую установку..."
    fi
fi

# ── ШАГ 4: Ввод параметров ────────────────────────────────────
log_step "ШАГ 4: Параметры установки"
echo ""
echo -e "${BOLD}Перед запуском:${NC}"
echo -e "  1. Создайте бота у @BotFather → получите токен"
echo -e "  2. Узнайте свой Telegram ID у @userinfobot"
echo -e "  3. Создайте API ключ в Remnawave: Настройки → API Keys → Создать"
echo ""

ask BOT_TOKEN  "* Токен бота от @BotFather"
ask ADMIN_IDS  "* Telegram ID администратора(ов) через запятую"
ask_secret REMNAWAVE_API_KEY "* API ключ Remnawave"

echo ""
echo -e "${BOLD}Telegram-группа уведомлений:${NC}"
echo -e "  ID группы/канала (начинается с -100...)"
echo -e "  Используется для всего: покупки, бэкапы, отчёты, логи"
echo ""
ask NOTIF_CHAT_ID "* ID группы (например: -1001234567890)"

echo ""
echo -e "  Топики (Enter = дефолт):"
echo -e "  ${YELLOW}Примечание:${NC} TOPIC_NODE используется для всех событий инфраструктуры"
echo -e "  (ноды + CRM-биллинг + сервис — Bedolaga не разделяет их по отдельным топикам)"
ask TOPIC_GENERAL "  Топик 2  — покупки/продления/триалы/баланс/промо" "2"
ask TOPIC_NODE    "  Топик 441 — ноды/CRM-биллинг/сервис/ошибки"       "441"
ask TOPIC_REPORTS "  Топик 6  — ежедневные отчёты о продажах"           "6"
ask TOPIC_TICKETS "  Топик 11 — тикеты поддержки"                       "11"
ask TOPIC_BACKUP  "  Топик 13 — бэкапы и ротация логов"                 "13"

echo ""
echo -e "${BOLD}Название сервиса (отображается пользователям):${NC}"
ask MINIAPP_NAME_RU "  Название (рус., например: TorchVPN)" "TorchVPN"
ask MINIAPP_NAME_EN "  Название (eng., например: TorchVPN)" "TorchVPN"

# ── ШАГ 5: Генерация секретов ─────────────────────────────────
log_step "ШАГ 5: Генерация секретов"

POSTGRES_PASSWORD=$(openssl rand -hex 24)
REMNAWAVE_WEBHOOK_SECRET=$(openssl rand -hex 32)
CABINET_JWT_SECRET=$(openssl rand -hex 32)
WEB_API_DEFAULT_TOKEN=$(openssl rand -hex 32)
DATABASE_URL="postgresql+asyncpg://remnawave_user:${POSTGRES_PASSWORD}@postgres:5432/remnawave_bot"

log_ok "Секреты сгенерированы"

# ── ШАГ 6: Клонирование репо ──────────────────────────────────
log_step "ШАГ 6: Клонирование репозитория"

git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
log_ok "Репозиторий → $INSTALL_DIR"

# ── ШАГ 7: Создание .env ──────────────────────────────────────
log_step "ШАГ 7: Создание .env"

cat > "$INSTALL_DIR/.env" << ENVEOF
# Bedolaga — сгенерировано $(date '+%Y-%m-%d %H:%M:%S')
# Редактировать: nano ${INSTALL_DIR}/.env
# Перезапустить: cd ${INSTALL_DIR} && docker compose restart bot

# ── Telegram ──────────────────────────────────────────────────
BOT_TOKEN=${BOT_TOKEN}
ADMIN_IDS=${ADMIN_IDS}
SUPPORT_USERNAME=@support
BOT_RUN_MODE=polling
WEBHOOK_DROP_PENDING_UPDATES=true
WEBHOOK_WORKERS=4

# ── База данных ───────────────────────────────────────────────
DATABASE_MODE=postgresql
DATABASE_URL=${DATABASE_URL}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=remnawave_bot
POSTGRES_USER=remnawave_user
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_POOL_SIZE=20
DATABASE_MAX_OVERFLOW=20
DATABASE_POOL_TIMEOUT=30

# ── Redis ─────────────────────────────────────────────────────
REDIS_URL=redis://redis:6379/0
CART_TTL_SECONDS=3600

# ── Remnawave API ─────────────────────────────────────────────
REMNAWAVE_API_URL=http://remnawave:3000
REMNAWAVE_API_KEY=${REMNAWAVE_API_KEY}
REMNAWAVE_AUTH_TYPE=api_key
REMNAWAVE_USER_DELETE_MODE=disable
REMNAWAVE_USER_DESCRIPTION_TEMPLATE=Bot user: {full_name} {username}
REMNAWAVE_USER_USERNAME_TEMPLATE=user_{telegram_id}
REMNAWAVE_AUTO_SYNC_ENABLED=true
REMNAWAVE_AUTO_SYNC_TIMES=03:00

# ── Remnawave Webhooks ────────────────────────────────────────
REMNAWAVE_WEBHOOK_ENABLED=true
REMNAWAVE_WEBHOOK_PATH=/remnawave-webhook
REMNAWAVE_WEBHOOK_SECRET=${REMNAWAVE_WEBHOOK_SECRET}
REMNAWAVE_WEBHOOK_NOTIFY_NODE_CONNECTION_STATUS=true

# Уведомления пользователю (личка)
WEBHOOK_NOTIFY_USER_ENABLED=true
WEBHOOK_NOTIFY_SUB_STATUS=true
# Подписка истекла → личка пользователя. Отключить = false
WEBHOOK_NOTIFY_SUB_EXPIRED=true
# "Подписка истекла 24ч назад" → личка. Чтобы отключить ТОЛЬКО для триала —
# отдельной настройки нет. Чтобы убрать для всех: WEBHOOK_NOTIFY_SUB_EXPIRED=false
WEBHOOK_NOTIFY_SUB_EXPIRING=true
WEBHOOK_NOTIFY_SUB_LIMITED=true
WEBHOOK_NOTIFY_TRAFFIC_RESET=true
WEBHOOK_NOTIFY_SUB_DELETED=true
WEBHOOK_NOTIFY_SUB_REVOKED=true
WEBHOOK_NOTIFY_FIRST_CONNECTED=true
WEBHOOK_NOTIFY_NOT_CONNECTED=true
WEBHOOK_NOTIFY_BANDWIDTH_THRESHOLD=true
WEBHOOK_NOTIFY_DEVICES=true
WEBHOOK_NOTIFY_TORRENT_DETECTED=true

# ── Уведомления администраторам ───────────────────────────────
ADMIN_NOTIFICATIONS_ENABLED=true
ADMIN_NOTIFICATIONS_CHAT_ID=${NOTIF_CHAT_ID}
ADMIN_NOTIFICATIONS_TOPIC_ID=${TOPIC_GENERAL}
ADMIN_NOTIFICATIONS_PURCHASES_TOPIC_ID=${TOPIC_GENERAL}
ADMIN_NOTIFICATIONS_RENEWALS_TOPIC_ID=${TOPIC_GENERAL}
ADMIN_NOTIFICATIONS_TRIALS_TOPIC_ID=${TOPIC_GENERAL}
ADMIN_NOTIFICATIONS_BALANCE_TOPIC_ID=${TOPIC_GENERAL}
ADMIN_NOTIFICATIONS_ADDONS_TOPIC_ID=${TOPIC_GENERAL}
ADMIN_NOTIFICATIONS_PROMO_TOPIC_ID=${TOPIC_GENERAL}
ADMIN_NOTIFICATIONS_INFRASTRUCTURE_TOPIC_ID=${TOPIC_NODE}
ADMIN_NOTIFICATIONS_ERRORS_TOPIC_ID=${TOPIC_NODE}
ADMIN_NOTIFICATIONS_TICKET_TOPIC_ID=${TOPIC_TICKETS}
SUSPICIOUS_NOTIFICATIONS_TOPIC_ID=${TOPIC_NODE}
ADMIN_NOTIFICATIONS_PARTNERS_TOPIC_ID=${TOPIC_GENERAL}

ADMIN_REPORTS_ENABLED=true
ADMIN_REPORTS_CHAT_ID=${NOTIF_CHAT_ID}
ADMIN_REPORTS_TOPIC_ID=${TOPIC_REPORTS}
ADMIN_REPORTS_SEND_TIME=03:00

# ── Поддержка и тикеты ────────────────────────────────────────
SUPPORT_MENU_ENABLED=true
SUPPORT_SYSTEM_MODE=both
SUPPORT_TICKET_SLA_ENABLED=true
SUPPORT_TICKET_SLA_MINUTES=60
SUPPORT_TICKET_SLA_CHECK_INTERVAL_SECONDS=300
SUPPORT_TICKET_SLA_REMINDER_COOLDOWN_MINUTES=120

# ── Бэкапы ────────────────────────────────────────────────────
BACKUP_AUTO_ENABLED=true
BACKUP_INTERVAL_HOURS=24
BACKUP_TIME=01:00
BACKUP_MAX_KEEP=7
BACKUP_COMPRESSION=true
BACKUP_INCLUDE_LOGS=true
BACKUP_LOCATION=/app/data/backups
BACKUP_SEND_ENABLED=true
BACKUP_SEND_CHAT_ID=${NOTIF_CHAT_ID}
BACKUP_SEND_TOPIC_ID=${TOPIC_BACKUP}

# ── Ротация логов ─────────────────────────────────────────────
LOG_ROTATION_ENABLED=true
LOG_ROTATION_TIME=00:00
LOG_ROTATION_KEEP_DAYS=7
LOG_ROTATION_COMPRESS=true
LOG_ROTATION_SEND_TO_TELEGRAM=true
LOG_ROTATION_CHAT_ID=${NOTIF_CHAT_ID}
LOG_ROTATION_TOPIC_ID=${TOPIC_BACKUP}

# ── Режим продаж и тарифы ─────────────────────────────────────
SALES_MODE=tariffs
MULTI_TARIFF_ENABLED=true
MAX_ACTIVE_SUBSCRIPTIONS=10
TARIFF_SWITCH_UPGRADE_ENABLED=true
TARIFF_SWITCH_DOWNGRADE_ENABLED=true
TARIFF_SWITCH_RESET_FREE_DAYS=true
RESET_DEVICES_ON_RENEWAL=false

# ── Триал ─────────────────────────────────────────────────────
TRIAL_DURATION_DAYS=3
TRIAL_TRAFFIC_LIMIT_GB=5
TRIAL_DEVICE_LIMIT=1
TRIAL_TARIFF_ID=0
TRIAL_PAYMENT_ENABLED=false
TRIAL_ACTIVATION_PRICE=0
TRIAL_ADD_REMAINING_DAYS_TO_PAID=false

# ── Параметры подписок ────────────────────────────────────────
DEFAULT_DEVICE_LIMIT=3
MAX_DEVICES_LIMIT=15
DEFAULT_TRAFFIC_LIMIT_GB=100
DEFAULT_TRAFFIC_RESET_STRATEGY=MONTH
RESET_TRAFFIC_ON_PAYMENT=false
AVAILABLE_SUBSCRIPTION_PERIODS=14,30,60,90,180,360
AVAILABLE_RENEWAL_PERIODS=14,30,60,90,180,360
TRAFFIC_TOPUP_ENABLED=true
BUY_TRAFFIC_BUTTON_VISIBLE=true
TRAFFIC_RESET_PRICE_MODE=traffic_with_purchased

# ── Реферальная система (выключена) ───────────────────────────
REFERRAL_PROGRAM_ENABLED=false
REFERRAL_PARTNER_SECTION_VISIBLE=false
REFERRAL_NOTIFICATIONS_ENABLED=false
REFERRAL_WITHDRAWAL_ENABLED=false
REFERRAL_CONTESTS_ENABLED=false
SKIP_REFERRAL_CODE=true

# ── Автопродление ─────────────────────────────────────────────
ENABLE_AUTOPAY=false
DEFAULT_AUTOPAY_ENABLED=true
DEFAULT_AUTOPAY_DAYS_BEFORE=3
AUTOPAY_FAIL_MAX_NOTIFICATIONS=2
AUTOPAY_FAIL_FINAL_REMINDER_HOURS=3

# ── Платёжные системы ─────────────────────────────────────────
# Telegram Stars — дефолтный метод (нативный, доп. настройки не нужны)
TELEGRAM_STARS_ENABLED=true
YOOKASSA_ENABLED=false
CRYPTOBOT_ENABLED=false
HELEKET_ENABLED=false
TRIBUTE_ENABLED=false
PAL24_ENABLED=false
PLATEGA_ENABLED=false
FREEKASSA_ENABLED=false
RIOPAY_ENABLED=false
SEVERPAY_ENABLED=false
PAYPEAR_ENABLED=false
ROLLYPAY_ENABLED=false
AURAPAY_ENABLED=false
WATA_ENABLED=false
CLOUDPAYMENTS_ENABLED=false
MULENPAY_ENABLED=false
APPLE_IAP_ENABLED=false

# ── Личный кабинет (выключен, настроить вручную) ──────────────
CABINET_ENABLED=false
CABINET_JWT_SECRET=${CABINET_JWT_SECRET}
CABINET_ACCESS_TOKEN_EXPIRE_MINUTES=15
CABINET_REFRESH_TOKEN_EXPIRE_DAYS=7

# ── Название сервиса (показывается пользователям) ─────────────
MINIAPP_SERVICE_NAME_RU=${MINIAPP_NAME_RU}
MINIAPP_SERVICE_NAME_EN=${MINIAPP_NAME_EN}

# ── Web API ───────────────────────────────────────────────────
WEB_API_ENABLED=true
WEB_API_HOST=0.0.0.0
WEB_API_PORT=8080
WEB_API_WORKERS=1
WEB_API_DOCS_ENABLED=false
WEB_API_DEFAULT_TOKEN=${WEB_API_DEFAULT_TOKEN}

# ── Мониторинг трафика (выключен) ─────────────────────────────
TRAFFIC_FAST_CHECK_ENABLED=false
TRAFFIC_DAILY_CHECK_ENABLED=false
BLACKLIST_CHECK_ENABLED=false

# ── Интерфейс ─────────────────────────────────────────────────
ENABLE_LOGO_MODE=false
MAIN_MENU_MODE=default
CONNECT_BUTTON_MODE=miniapp_subscription
HIDE_SUBSCRIPTION_LINK=false
DISABLE_WEB_PAGE_PREVIEW=false
SKIP_RULES_ACCEPT=false
ENABLE_DEEP_LINKS=true
PRICE_ROUNDING_ENABLED=true
LANGUAGE_SELECTION_ENABLED=true
DEFAULT_LANGUAGE=ru
AVAILABLE_LANGUAGES=ru,en,ua,zh,fa

# ── Системные ─────────────────────────────────────────────────
TZ=Europe/Moscow
LOG_LEVEL=INFO
LOG_COLORS=true
LOG_DIR=logs
MONITORING_INTERVAL=60
ENABLE_NOTIFICATIONS=true
NOTIFICATION_RETRY_ATTEMPTS=3
INACTIVE_USER_DELETE_MONTHS=12
MAINTENANCE_MODE=false
MAINTENANCE_AUTO_ENABLE=true
MAINTENANCE_MONITORING_ENABLED=true
NALOGO_ENABLED=false
VERSION_CHECK_ENABLED=true
VERSION_CHECK_REPO=BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot
VERSION_CHECK_INTERVAL_HOURS=6
DEBUG=false
APP_CONFIG_CACHE_TTL=3600
ENVEOF

chmod 600 "$INSTALL_DIR/.env"
log_ok ".env создан"

# ── ШАГ 8: docker-compose.override.yml ───────────────────────
log_step "ШАГ 8: Подключение к сети Remnawave"

cat > "$INSTALL_DIR/docker-compose.override.yml" << 'OVERRIDE_EOF'
networks:
  remnawave-network:
    name: remnawave-network
    external: true

services:
  bot:
    networks:
      bot_network:
      remnawave-network:
        aliases:
          - remnawave_bot
OVERRIDE_EOF

log_ok "docker-compose.override.yml создан (alias: remnawave_bot)"

# ── ШАГ 9: Сборка и запуск ────────────────────────────────────
log_step "ШАГ 9: Сборка Docker-образа (2–5 минут)"
cd "$INSTALL_DIR"
docker compose build --pull

log_step "ШАГ 10: Запуск Bedolaga"

# Создаём директории которые монтируются в контейнер (бот запускается как UID 1000:1000)
mkdir -p "$INSTALL_DIR"/{data/backups,logs/current,locales,uploads}
chmod -R 777 "$INSTALL_DIR"/{data,logs,locales,uploads}

docker compose up -d

# ── ШАГ 11: Настройка вебхука в Remnawave ─────────────────────
log_step "ШАГ 11: Настройка вебхука в Remnawave"

REMNAWAVE_ENV="$REMNAWAVE_DIR/.env"

if [[ ! -f "$REMNAWAVE_ENV" ]]; then
    log_warn "Файл $REMNAWAVE_ENV не найден — пропускаю автонастройку"
    log_warn "Пропишите вручную:"
    echo -e "  WEBHOOK_ENABLED=true"
    echo -e "  WEBHOOK_URL=http://remnawave_bot:8080/remnawave-webhook"
    echo -e "  WEBHOOK_SECRET_HEADER=${REMNAWAVE_WEBHOOK_SECRET}"
else
    RW_ENV_BACKUP="${REMNAWAVE_ENV}.bak.$(date +%F-%H%M%S)"
    cp "$REMNAWAVE_ENV" "$RW_ENV_BACKUP"
    log_ok "Бэкап Remnawave .env: $RW_ENV_BACKUP"

    set_env "WEBHOOK_ENABLED"       "true"                                        "$REMNAWAVE_ENV"
    set_env "WEBHOOK_URL"           "http://remnawave_bot:8080/remnawave-webhook" "$REMNAWAVE_ENV"
    set_env "WEBHOOK_SECRET_HEADER" "${REMNAWAVE_WEBHOOK_SECRET}"                 "$REMNAWAVE_ENV"
    log_ok "Вебхук прописан"

    log_info "Перезапускаю Remnawave..."
    cd "$REMNAWAVE_DIR"
    docker compose restart remnawave
    log_ok "Remnawave перезапущена"
    cd "$INSTALL_DIR"

    # Бэкап больше не нужен для отката — установка успешна
    RW_ENV_BACKUP=""
fi

# ── ШАГ 12: TLS-уведомления через certbot hook ────────────────
log_step "ШАГ 12: Установка TLS-уведомлений"

CERTBOT_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
CERTBOT_HOOK_FILE="$CERTBOT_HOOK_DIR/bedolaga-tls-notify.sh"

if command -v certbot &>/dev/null && [[ -d "/etc/letsencrypt" ]]; then
    mkdir -p "$CERTBOT_HOOK_DIR"
    # Универсальный хук: работает на панели (/opt/bedolaga/.env)
    # и на нодах (/etc/bedolaga-notify.env). NODE_NAME — из env или hostname.
    cat > "$CERTBOT_HOOK_FILE" << 'HOOKEOF'
#!/bin/bash
# Certbot deploy hook — универсальный (панель + ноды).
# Certbot передаёт: $RENEWED_LINEAGE, $RENEWED_DOMAINS
set -euo pipefail
ENV_FILE=""
for _f in "/opt/bedolaga/.env" "/etc/bedolaga-notify.env"; do
    [[ -f "$_f" ]] && { ENV_FILE="$_f"; break; }
done
[[ -z "$ENV_FILE" ]] && exit 0
_get() { grep -m1 "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d "\"' " || true; }
export BOT_TOKEN; BOT_TOKEN=$(_get BOT_TOKEN)
export CHAT_ID;   CHAT_ID=$(_get BACKUP_SEND_CHAT_ID)
export TOPIC_ID;  TOPIC_ID=$(_get BACKUP_SEND_TOPIC_ID)
export NODE_NAME; NODE_NAME=$(_get NODE_NAME)
[[ -z "$NODE_NAME" ]] && NODE_NAME=$(hostname -s 2>/dev/null || echo "server")
[[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]] && exit 0
export CERT_EXPIRY
CERT_EXPIRY=$(openssl x509 -noout -enddate \
    -in "${RENEWED_LINEAGE}/cert.pem" 2>/dev/null \
    | sed 's/notAfter=//' \
    | xargs -I{} date -d "{}" '+%d.%m.%Y' 2>/dev/null || echo "—")
python3 - <<'PYEOF'
import os, json, sys, urllib.request
token     = os.environ["BOT_TOKEN"]
chat      = os.environ["CHAT_ID"]
topic     = os.environ.get("TOPIC_ID", "")
lineage   = os.environ.get("RENEWED_LINEAGE", "")
domains   = os.environ.get("RENEWED_DOMAINS", "").split()
expiry    = os.environ.get("CERT_EXPIRY", "—")
node_name = os.environ.get("NODE_NAME", "server")
domain_lines = "\n".join(f"• <code>{d}</code>" for d in domains)
text = (
    "🔒 <b>TLS-сертификат обновлён</b>\n\n"
    f"🖥 <b>Сервер:</b> <code>{node_name}</code>\n"
    f"🌐 <b>Домены:</b>\n{domain_lines}\n\n"
    f"📅 <b>Действует до:</b> <code>{expiry}</code>\n"
    f"📂 <b>Путь:</b> <code>{lineage}</code>\n\n"
    "<i>#tls #certbot #bedolaga</i>"
)
payload = {"chat_id": chat, "text": text, "parse_mode": "HTML"}
if topic:
    try:
        payload["message_thread_id"] = int(topic)
    except ValueError:
        pass
req = urllib.request.Request(
    f"https://api.telegram.org/bot{token}/sendMessage",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)
try:
    urllib.request.urlopen(req, timeout=10)
except Exception as e:
    print(f"TLS notify failed: {e}", file=sys.stderr)
    sys.exit(0)
PYEOF
exit 0
HOOKEOF
    chmod +x "$CERTBOT_HOOK_FILE"
    log_ok "TLS-хук → $CERTBOT_HOOK_FILE"
    log_info "При каждом обновлении сертификата — уведомление в Telegram (топик 13)"
else
    log_warn "certbot не найден — TLS-уведомления не настроены"
fi

# ── ШАГ 13: Проверка ──────────────────────────────────────────
log_step "ШАГ 13: Проверка состояния"

echo -n "Жду старта бота"
for i in {1..18}; do
    sleep 5; echo -n "."
    status=$(docker compose -f "$INSTALL_DIR/docker-compose.yml" \
        -f "$INSTALL_DIR/docker-compose.override.yml" \
        ps --format '{{.Service}} {{.State}}' 2>/dev/null | \
        grep '^bot' | awk '{print $2}' || true)
    [[ "$status" == "running" ]] && { echo ""; break; }
done
echo ""

cd "$INSTALL_DIR"
docker compose ps

# ── Успех ─────────────────────────────────────────────────────
INSTALL_OK=true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗"
echo -e "║   Bedolaga установлена!                             ║"
echo -e "╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Директория:  ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  Конфиг:      ${CYAN}${INSTALL_DIR}/.env${NC}"
echo -e "  Команда:     ${CYAN}bedolaga${NC} (повторная установка / обновление)"
echo ""
echo -e "${BOLD}Управление:${NC}"
echo -e "  Логи:        ${CYAN}cd ${INSTALL_DIR} && docker compose logs -f bot${NC}"
echo -e "  Перезапуск:  ${CYAN}cd ${INSTALL_DIR} && docker compose restart bot${NC}"
echo -e "  Остановка:   ${CYAN}cd ${INSTALL_DIR} && docker compose down${NC}"
echo -e "  Обновление:  ${CYAN}bedolaga${NC}"
echo ""
echo -e "${BOLD}Следующие шаги:${NC}"
echo -e "  1. Напишите боту /start в Telegram"
echo -e "  2. Создайте тарифы в Remnawave Panel → Тарифы"
echo -e "  3. Включите платёжную систему в ${CYAN}${INSTALL_DIR}/.env${NC}"
echo ""
echo -e "${YELLOW}Последние логи бота:${NC}"
docker compose logs --tail=20 bot 2>&1 || true
