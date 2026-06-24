#!/bin/bash
# install_node_tls_hook.sh — установка TLS-уведомлений на сервере НОДЫ
#
# Запускать на каждом сервере ноды (не панели):
#   bash install_node_tls_hook.sh
#
# Что делает:
#   1. Создаёт /etc/bedolaga-notify.env с параметрами уведомлений
#   2. Устанавливает certbot deploy hook в /etc/letsencrypt/renewal-hooks/deploy/
#   3. Тестирует отправку уведомления

set -euo pipefail

HOOK_URL="https://raw.githubusercontent.com/FnoUp/bedolaga_installer/main/certbot_tls_hook.sh"
HOOK_FILE="/etc/letsencrypt/renewal-hooks/deploy/bedolaga-tls-notify.sh"
CONFIG_FILE="/etc/bedolaga-notify.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
log_info() { echo -e "${CYAN}[→]${NC} $*"; }

ask() {
    local _var=$1 _msg=$2 _def=${3:-}
    local _val
    if [[ -n "$_def" ]]; then
        read -rp $'\e[0;36m?\e[0m '"$_msg [$_def]: " _val
        _val="${_val:-$_def}"
    else
        read -rp $'\e[0;36m?\e[0m '"$_msg: " _val
    fi
    [[ -z "$_val" ]] && { log_err "Обязательное поле"; exit 1; }
    printf -v "$_var" '%s' "$_val"
}

ask_secret() {
    local _var=$1 _msg=$2 _val
    read -srp $'\e[0;36m?\e[0m '"$_msg: " _val; echo
    [[ -z "$_val" ]] && { log_err "Обязательное поле"; exit 1; }
    printf -v "$_var" '%s' "$_val"
}

[[ $EUID -ne 0 ]] && { log_err "Запустите от root: sudo bash install_node_tls_hook.sh"; exit 1; }

command -v certbot &>/dev/null || { log_err "certbot не найден на этом сервере"; exit 1; }
[[ -d "/etc/letsencrypt" ]] || { log_err "/etc/letsencrypt не найден — certbot не установлен?"; exit 1; }

echo -e "\n${BOLD}${CYAN}━━━ Bedolaga TLS Hook — Установка на ноде ━━━${NC}\n"

echo -e "${BOLD}Параметры (берутся из настроек бота на панели):${NC}"
ask_secret BOT_TOKEN   "Токен бота (из /opt/bedolaga/.env → BOT_TOKEN)"
ask CHAT_ID  "ID чата для уведомлений (ADMIN_NOTIFICATIONS_CHAT_ID)" "-1001234567890"
ask TOPIC_ID "Топик 13 — бекапы/TLS (BACKUP_SEND_TOPIC_ID)"         "13"
ask NODE_NAME "Название этой ноды (для уведомлений)"                 "France-01"

# Создаём конфиг
cat > "$CONFIG_FILE" << CONFEOF
# Bedolaga TLS Notify — конфиг для ноды ${NODE_NAME}
# Генерировано: $(date '+%Y-%m-%d %H:%M:%S')
BOT_TOKEN=${BOT_TOKEN}
BACKUP_SEND_CHAT_ID=${CHAT_ID}
BACKUP_SEND_TOPIC_ID=${TOPIC_ID}
NODE_NAME=${NODE_NAME}
CONFEOF

chmod 600 "$CONFIG_FILE"
log_ok "Конфиг создан: $CONFIG_FILE"

# Скачиваем hook
mkdir -p "$(dirname "$HOOK_FILE")"
if curl -fsSL "$HOOK_URL" -o "$HOOK_FILE"; then
    chmod +x "$HOOK_FILE"
    log_ok "Хук установлен: $HOOK_FILE"
else
    log_err "Не удалось скачать хук с GitHub"
    log_warn "Скопируйте certbot_tls_hook.sh вручную в $HOOK_FILE"
    exit 1
fi

# Тест: берём первый найденный lineage
TEST_LINEAGE=$(certbot certificates 2>/dev/null | grep 'Certificate Path' | head -1 | awk '{print $NF}' | xargs dirname 2>/dev/null || true)
if [[ -z "$TEST_LINEAGE" ]]; then
    TEST_LINEAGE=$(ls -d /etc/letsencrypt/live/*/ 2>/dev/null | grep -v README | head -1 || true)
fi

if [[ -n "$TEST_LINEAGE" ]]; then
    echo ""
    log_info "Тест отправки уведомления..."
    RENEWED_LINEAGE="$TEST_LINEAGE" \
    RENEWED_DOMAINS="$(basename "$TEST_LINEAGE")" \
    bash "$HOOK_FILE" && log_ok "Уведомление отправлено в Telegram (топик $TOPIC_ID)" || log_warn "Ошибка отправки — проверьте токен и CHAT_ID"
else
    log_warn "Нет активных сертификатов для теста — хук установлен, проверьте после следующего обновления"
fi

echo ""
log_ok "Готово! При каждом обновлении сертификата придёт уведомление в топик ${TOPIC_ID}."
echo -e "  Конфиг:   ${CYAN}${CONFIG_FILE}${NC}"
echo -e "  Хук:      ${CYAN}${HOOK_FILE}${NC}"
