#!/bin/bash
# /etc/letsencrypt/renewal-hooks/deploy/bedolaga-tls-notify.sh
#
# Certbot deploy hook — уведомление в Telegram (топик 13) после обновления TLS-сертификата.
# Certbot вызывает этот скрипт автоматически при каждом УСПЕШНОМ обновлении.
#
# Certbot передаёт переменные:
#   $RENEWED_LINEAGE — путь к обновлённому lineage (/etc/letsencrypt/live/<domain>)
#   $RENEWED_DOMAINS — домены через пробел (например: "example.com www.example.com")

set -euo pipefail

ENV_FILE="/opt/bedolaga/.env"

# Бот не настроен — выходим без ошибки
[[ ! -f "$ENV_FILE" ]] && exit 0

# Читаем значение из .env (убираем кавычки и пробелы)
_get() { grep -m1 "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d "\"' " || true; }

export BOT_TOKEN; BOT_TOKEN=$(_get BOT_TOKEN)
export CHAT_ID;   CHAT_ID=$(_get BACKUP_SEND_CHAT_ID)
export TOPIC_ID;  TOPIC_ID=$(_get BACKUP_SEND_TOPIC_ID)

[[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]] && exit 0

# Дата окончания нового сертификата
export CERT_EXPIRY
CERT_EXPIRY=$(openssl x509 -noout -enddate \
    -in "${RENEWED_LINEAGE}/cert.pem" 2>/dev/null \
    | sed 's/notAfter=//' \
    | xargs -I{} date -d "{}" '+%d.%m.%Y' 2>/dev/null || echo "—")

# Отправка через Python (правильный JSON, нет проблем с экранированием)
python3 - <<'PYEOF'
import os, json, urllib.request, sys

token   = os.environ["BOT_TOKEN"]
chat    = os.environ["CHAT_ID"]
topic   = os.environ.get("TOPIC_ID", "")
lineage = os.environ.get("RENEWED_LINEAGE", "")
domains = os.environ.get("RENEWED_DOMAINS", "").split()
expiry  = os.environ.get("CERT_EXPIRY", "—")

domain_lines = "\n".join(f"• <code>{d}</code>" for d in domains)

text = (
    "🔒 <b>TLS-сертификат обновлён</b>\n\n"
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
    sys.exit(0)  # не блокируем certbot при ошибке отправки
PYEOF

exit 0
