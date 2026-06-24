#!/bin/bash
# certbot_tls_hook.sh — универсальный Certbot deploy hook
#
# Работает на ЛЮБОМ сервере (панель + ноды).
# Certbot вызывает его автоматически после каждого успешного обновления.
#
# Переменные certbot:
#   $RENEWED_LINEAGE — путь к lineage (/etc/letsencrypt/live/<domain>)
#   $RENEWED_DOMAINS — домены через пробел
#
# Конфиг ищется в порядке приоритета:
#   1. /opt/bedolaga/.env         (панель — полный env бота)
#   2. /etc/bedolaga-notify.env   (нода — минимальный конфиг)
#
# Минимальный /etc/bedolaga-notify.env для ноды:
#   BOT_TOKEN=<токен бота>
#   BACKUP_SEND_CHAT_ID=<ID чата>
#   BACKUP_SEND_TOPIC_ID=13
#   NODE_NAME=France-01

set -euo pipefail

# Поиск конфига
ENV_FILE=""
for _f in "/opt/bedolaga/.env" "/etc/bedolaga-notify.env"; do
    [[ -f "$_f" ]] && { ENV_FILE="$_f"; break; }
done
[[ -z "$ENV_FILE" ]] && exit 0

# Читаем значение из env-файла (убираем кавычки и пробелы)
_get() { grep -m1 "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d "\"' " || true; }

export BOT_TOKEN;  BOT_TOKEN=$(_get BOT_TOKEN)
export CHAT_ID;    CHAT_ID=$(_get BACKUP_SEND_CHAT_ID)
export TOPIC_ID;   TOPIC_ID=$(_get BACKUP_SEND_TOPIC_ID)
export NODE_NAME;  NODE_NAME=$(_get NODE_NAME)
[[ -z "$NODE_NAME" ]] && NODE_NAME=$(hostname -s 2>/dev/null || echo "server")

[[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]] && exit 0

# Дата окончания нового сертификата (GNU date, Linux)
export CERT_EXPIRY
CERT_EXPIRY=$(openssl x509 -noout -enddate \
    -in "${RENEWED_LINEAGE}/cert.pem" 2>/dev/null \
    | sed 's/notAfter=//' \
    | xargs -I{} date -d "{}" '+%d.%m.%Y' 2>/dev/null || echo "—")

# Отправка через Python — корректный JSON без проблем экранирования
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
    sys.exit(0)  # не блокируем certbot
PYEOF

exit 0
