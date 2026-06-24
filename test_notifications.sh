#!/bin/bash
# test_notifications.sh — симуляция всех уведомлений Bedolaga
# Запуск: bash test_notifications.sh [--all | --admin | --user | --event user.expired]
#
# Уведомления делятся на 2 категории:
#   ADMIN  — всегда работают (нода, сервис, CRM) → в admin-чат
#   USER   — нужен реальный пользователь в БД (прошёл /start в боте)

set -euo pipefail

WEBHOOK_URL="http://localhost:8080/remnawave-webhook"
ENV_FILE="/opt/bedolaga/.env"

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_err()  { echo -e "  ${RED}✗${NC} $1"; }
log_info() { echo -e "  ${CYAN}→${NC} $1"; }
banner()   { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

# ── Получаем секрет из .env ────────────────────────────────────────────────────
SECRET=$(grep '^REMNAWAVE_WEBHOOK_SECRET=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"'"'"' ')
TELEGRAM_ID=$(grep '^ADMIN_IDS=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"'"'"' ' | cut -d',' -f1)

if [[ -z "$SECRET" ]]; then
    log_err "REMNAWAVE_WEBHOOK_SECRET не найден в $ENV_FILE"
    exit 1
fi

log_info "Секрет: ${SECRET:0:8}...${SECRET: -4}"
log_info "Admin TG ID: $TELEGRAM_ID"

# ── Функции ───────────────────────────────────────────────────────────────────

# Подписываем и отправляем вебхук
send_event() {
    local event="$1"
    local data="$2"
    local scope="${event%%.*}"

    local payload
    payload=$(printf '{"event":"%s","scope":"%s","data":%s}' "$event" "$scope" "$data")

    local sig
    sig=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$SECRET" 2>/dev/null | awk '{print $NF}')

    local resp
    resp=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -H "X-Remnawave-Signature: $sig" \
        -d "$payload" 2>/dev/null)

    local body http_code
    body=$(echo "$resp" | head -n -1)
    http_code=$(echo "$resp" | tail -n 1)

    local processed
    processed=$(echo "$body" | grep -o '"processed":[^,}]*' | cut -d: -f2 | tr -d ' ')

    if [[ "$http_code" == "200" ]]; then
        if [[ "$processed" == "true" ]]; then
            log_ok "[$event] HTTP $http_code — отправлено в чат"
        elif [[ "$processed" == "false" ]]; then
            log_warn "[$event] HTTP $http_code — принято, но не обработано (пользователь не найден в БД?)"
        else
            log_ok "[$event] HTTP $http_code"
        fi
    elif [[ "$http_code" == "401" ]]; then
        log_err "[$event] HTTP $http_code — неверная подпись"
    else
        log_err "[$event] HTTP $http_code — $body"
    fi
}

# Данные тестового пользователя (нужен /start завершённый в боте)
USER_DATA() {
    cat <<EOF
{
  "uuid": "test-uuid-00000000-0000-0000-0000-000000000001",
  "telegramId": $TELEGRAM_ID,
  "username": "user_${TELEGRAM_ID}",
  "email": null,
  "expireAt": "2026-07-24T00:00:00.000Z",
  "trafficLimitBytes": 107374182400,
  "usedTrafficBytes": 5368709120,
  "status": "ACTIVE",
  "shortUuid": "testABC",
  "subscriptionUrl": "vless://test@fr.vpn.example.com:443?security=reality"
}
EOF
}


# ──────────────────────────────────────────────────────────────────────────────
# ADMIN СОБЫТИЯ — только сервис и CRM через webhook (→ топик INFRA)
# Node события теперь только в sim_topics.py (→ топик NODE/441 и TRAFFIC/6)
# ──────────────────────────────────────────────────────────────────────────────

run_admin_events() {
    banner "СЕРВИС: панель Remnawave (→ топик INFRA)"
    send_event "service.panel_started"           '{"version":"1.0.0","reason":"scheduled restart"}'
    send_event "service.login_attempt_success"   '{"ip":"192.168.1.100","userAgent":"Mozilla/5.0"}'
    send_event "service.login_attempt_failed"    '{"ip":"192.168.1.200","userAgent":"curl/7.88"}'
    send_event "service.subpage_config_changed"  '{"reason":"config updated"}'

    banner "CRM: биллинг ноды (→ топик INFRA)"
    CRM_NODE='{"nodeUuid":"node-uuid-france-01","nodeName":"France-01","amount":1500,"currency":"RUB"}'
    send_event "crm.infra_billing_node_payment_in_7_days"      "$CRM_NODE"
    send_event "crm.infra_billing_node_payment_in_48hrs"       "$CRM_NODE"
    send_event "crm.infra_billing_node_payment_in_24hrs"       "$CRM_NODE"
    send_event "crm.infra_billing_node_payment_due_today"      "$CRM_NODE"
    send_event "crm.infra_billing_node_payment_overdue_24hrs"  "$CRM_NODE"
    send_event "crm.infra_billing_node_payment_overdue_48hrs"  "$CRM_NODE"
    send_event "crm.infra_billing_node_payment_overdue_7_days" "$CRM_NODE"

    banner "СИСТЕМА: ошибки (→ топик INFRA)"
    send_event "errors.bandwidth_usage_threshold_reached_max_notifications" '{"userId":"test-uuid","count":5}'
}

# ──────────────────────────────────────────────────────────────────────────────
# USER СОБЫТИЯ — нужен пользователь в БД (завершил /start)
# ──────────────────────────────────────────────────────────────────────────────

run_user_events() {
    local ud
    ud=$(USER_DATA)

    echo -e "\n${YELLOW}⚠  Пользовательские события работают только если TG ID ${TELEGRAM_ID} завершил /start в боте!${NC}"

    banner "ПОДПИСКА: статусы"
    send_event "user.expired"   "$ud"
    send_event "user.disabled"  "$ud"
    send_event "user.enabled"   "$ud"
    send_event "user.limited"   "$ud"
    send_event "user.revoked"   "$ud"
    send_event "user.deleted"   "$ud"

    banner "ПОДПИСКА: изменение и создание"
    MODIFIED=$(echo "$ud" | sed 's/"status":"ACTIVE"/"status":"ACTIVE","previousStatus":"DISABLED"/')
    send_event "user.modified" "$MODIFIED"
    send_event "user.created"  "$ud"

    banner "ПОДПИСКА: истекает скоро"
    EXPIRING=$(echo "$ud" | sed 's/2026-07-24/2026-06-27/')
    send_event "user.expires_in_72_hours" "$EXPIRING"
    send_event "user.expires_in_48_hours" "$EXPIRING"
    send_event "user.expires_in_24_hours" "$EXPIRING"
    send_event "user.expired_24_hours_ago" "$ud"

    banner "ПОДПИСКА: трафик"
    send_event "user.traffic_reset"  "$ud"
    BANDWIDTH=$(echo "$ud" | sed 's/"usedTrafficBytes":5368709120/"usedTrafficBytes":96636764160/')
    send_event "user.bandwidth_usage_threshold_reached" "$BANDWIDTH"

    banner "ПОДКЛЮЧЕНИЕ"
    send_event "user.first_connected" "$ud"
    NOT_CONNECTED=$(echo "$ud" | sed 's/"status":"ACTIVE"/"status":"ACTIVE","createdAt":"2026-06-17T00:00:00.000Z"/')
    send_event "user.not_connected" "$NOT_CONNECTED"

    banner "УСТРОЙСТВА"
    DEVICE_DATA=$(printf '{
      "uuid": "device-uuid-001",
      "hwid": "HWID-ABCDEF123456",
      "userUuid": "test-uuid-00000000-0000-0000-0000-000000000001",
      "telegramId": %s,
      "user": {"uuid":"test-uuid-00000000-0000-0000-0000-000000000001","telegramId":%s},
      "platform": "Windows",
      "userAgent": "xray/1.8.0"
    }' "$TELEGRAM_ID" "$TELEGRAM_ID")
    send_event "user_hwid_devices.added"   "$DEVICE_DATA"
    send_event "user_hwid_devices.deleted" "$DEVICE_DATA"

    banner "ТОРРЕНТ-БЛОКИРОВЩИК"
    TORRENT_DATA=$(printf '{
      "uuid": "test-uuid-00000000-0000-0000-0000-000000000001",
      "telegramId": %s,
      "username": "user_%s",
      "nodeUuid": "node-uuid-france-01",
      "nodeName": "France-01",
      "protocol": "bittorrent",
      "detectedAt": "2026-06-24T10:00:00.000Z"
    }' "$TELEGRAM_ID" "$TELEGRAM_ID")
    send_event "torrent_blocker.report" "$TORRENT_DATA"
}

# ──────────────────────────────────────────────────────────────────────────────
# Внутренние уведомления бота (покупки/триалы/тикеты/бекапы) через Python
# ──────────────────────────────────────────────────────────────────────────────

SIM_SCRIPT="$(cd "$(dirname "$0")" && pwd)/sim_topics.py"

run_internal_events() {
    if [[ ! -f "$SIM_SCRIPT" ]]; then
        log_warn "sim_topics.py не найден рядом со скриптом — пропускаю внутренние события"
        return
    fi
    banner "ВНУТРЕННИЕ СОБЫТИЯ БОТА (топики 2, 11, 13)"
    docker cp "$SIM_SCRIPT" remnawave_bot:/tmp/sim_topics.py >/dev/null 2>&1
    docker exec remnawave_bot python /tmp/sim_topics.py
}

# ──────────────────────────────────────────────────────────────────────────────
# ЗАПУСК
# ──────────────────────────────────────────────────────────────────────────────

MODE="${1:---all}"
EVENT_FILTER="${2:-}"

case "$MODE" in
    --admin)
        banner "ТОЛЬКО ADMIN-УВЕДОМЛЕНИЯ (webhook → топик 4)"
        run_admin_events
        ;;
    --user)
        banner "ТОЛЬКО USER-УВЕДОМЛЕНИЯ (webhook → личка)"
        run_user_events
        ;;
    --internal)
        run_internal_events
        ;;
    --event)
        if [[ -z "$EVENT_FILTER" ]]; then
            log_err "Укажи событие: --event user.expired"
            exit 1
        fi
        banner "ОДИНОЧНОЕ СОБЫТИЕ: $EVENT_FILTER"
        send_event "$EVENT_FILTER" "$(USER_DATA)"
        ;;
    --tls-test)
        banner "ТЕСТ TLS-ХУКА (certbot deploy hook)"
        HOOK="/etc/letsencrypt/renewal-hooks/deploy/bedolaga-tls-notify.sh"
        if [[ ! -f "$HOOK" ]]; then
            log_err "Хук не установлен: $HOOK"
            log_info "Установите: bash /opt/bedolaga/install_bedolaga.sh"
            exit 1
        fi
        RENEWED_LINEAGE="/etc/letsencrypt/live/vpn.example.com" \
        RENEWED_DOMAINS="vpn.example.com sub.vpn.example.com" \
        bash "$HOOK" && log_ok "TLS-уведомление отправлено в топик 13" || log_err "Ошибка отправки"
        ;;
    --all|*)
        banner "ВСЕ УВЕДОМЛЕНИЯ"
        run_admin_events
        run_user_events
        run_internal_events
        ;;
esac

CHAT_ID=$(grep '^ADMIN_NOTIFICATIONS_CHAT_ID=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"'"'"' ')
echo -e "\n${GREEN}${BOLD}Готово!${NC} Проверь чат ${CHAT_ID:-"(см. .env)"} в Telegram."
echo -e "Логи бота: ${CYAN}cd /opt/bedolaga && docker compose logs -f bot${NC}"
