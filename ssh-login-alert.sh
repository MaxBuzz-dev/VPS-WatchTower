#!/bin/bash
#=============================================================================
# SSH LOGIN ALERT — sends Telegram notification on every successful SSH login
# Self-contained — uses Telegram Bot API directly, no dependencies
# Part of VPS WatchTower (https://github.com/MaxBuzz-dev/VPS-WatchTower)
#
# Install:
#   1. Set BOT_TOKEN, CHAT_ID, and SERVER_NAME below
#   2. Copy to /root/ssh-telegram-alert.sh
#   3. Add to /etc/ssh/sshrc: /root/ssh-telegram-alert.sh "$1"
#   4. Create /etc/ssh/sshrc if it doesn't exist
#=============================================================================

# === CONFIGURABLE ===
BOT_TOKEN="YOUR_BOT_TOKEN_HERE"
CHAT_ID="YOUR_CHAT_ID_HERE"
SERVER_NAME="My Server"
# ====================

# Background immediately so SSH doesn't wait
if [ "$1" != "--no-fork" ]; then
  SSH_USER="$1"
  bash "$0" --no-fork "$SSH_USER" &
  exit 0
fi

USERNAME="${2:-$(whoami)}"
IP_ADDR=$(echo "$SSH_CONNECTION" | awk '{print $1}')
NOW=$(date '+%d %b %Y, %H:%M UTC')

# Skip localhost
[ "$IP_ADDR" = "127.0.0.1" ] && exit 0
[ -z "$IP_ADDR" ] && exit 0

# Dedup: same IP+user within 60s
DEDUP_FILE="/tmp/.ssh-login-dedup"
NOW_TS=$(date +%s)
if [ -f "$DEDUP_FILE" ]; then
  while IFS='|' read -r ip user ts; do
    [ "$ip" = "$IP_ADDR" ] && [ "$user" = "$USERNAME" ] && \
      [ $((NOW_TS - ts)) -lt 60 ] && exit 0
  done < "$DEDUP_FILE"
fi
echo "${IP_ADDR}|${USERNAME}|${NOW_TS}" >> "$DEDUP_FILE"

# Prune old entries
ENTRIES=$(wc -l < "$DEDUP_FILE")
if [ "$ENTRIES" -gt 50 ]; then
  awk -F'|' -v now="$NOW_TS" '$3 > (now - 600)' "$DEDUP_FILE" > "${DEDUP_FILE}.tmp" && \
    mv "${DEDUP_FILE}.tmp" "$DEDUP_FILE"
fi

# Geo lookup
GEO=$(curl -s --max-time 5 "http://ip-api.com/json/${IP_ADDR}" 2>/dev/null)
CITY=$(echo "$GEO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('city','?') or '?')" 2>/dev/null)
COUNTRY=$(echo "$GEO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('country','?') or '?')" 2>/dev/null)
ISP=$(echo "$GEO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('isp','?') or '?')" 2>/dev/null)

# Send via Telegram Bot API directly
MESSAGE="🔑 SSH Login - $USERNAME
🖥 $SERVER_NAME
IP: $IP_ADDR
📍 $CITY, $COUNTRY
🏢 $ISP
⏰ $NOW"

curl -s --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=${MESSAGE}" > /dev/null 2>&1
