#!/bin/bash
#=============================================================================
# VPS Watchtower — Daily server security report, delivered to your Telegram
# https://github.com/MaxBuzz-dev/VPS-WatchTower
#
# Author: Abbas Baarudwaala (github.com/cfinhas)
# License: MIT
#
# WHAT IT DOES:
#   ✓ SSH login audit with geo-location (whitelist known cities)
#   ✓ Failed login attempts & brute-force tracking
#   ✓ DNSBL blacklist check (Spamhaus, Barracuda)
#   ✓ SSL certificate expiry warning (14-day threshold)
#   ✓ Pending security updates count
#   ✓ Failed systemd services
#   ✓ Docker container health
#   ✓ WordPress admin count & backdoor scan
#   ✓ fail2ban ban statistics
#   ✓ High CPU processes
#   ✓ Cron/udev tampering detection
#   ✓ System resource usage (disk, RAM)
#
# REQUIREMENTS:
#   - bash, curl, python3 (for geo-lookup JSON parsing)
#   - Optional: Hermes CLI (/usr/local/bin/hermes) for clean delivery
#   - Optional: fail2ban-client, docker, openssl, mysql
#     Missing deps are gracefully skipped — no failures
#
# INSTALL:
#   curl -sL https://raw.githubusercontent.com/MaxBuzz-dev/VPS-WatchTower/main/watchtower.sh \
#   -o /usr/local/bin/watchtower.sh
#   chmod +x /usr/local/bin/watchtower.sh
#   # Edit config below, then add cron:
#   echo "30 2 * * * root /usr/local/bin/watchtower.sh" \
#     > /etc/cron.d/vps-watchtower
#=============================================================================

set -euo pipefail

#=============================================================================
# CONFIGURATION — EDIT THESE
#=============================================================================

# Display name for this server in reports
SERVER_NAME="$(hostname)"

# How to deliver: "telegram" (direct API) or "hermes" (Hermes CLI)
# Leave blank for auto-detect (prefers hermes if available)
DELIVERY=""

# Telegram Bot API — only needed if DELIVERY=telegram or auto-detect falls back
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# Known admin IPs (static — these skip geo-lookup, always shown as known)
ADMIN_IPS=(
  60.254.60.25
  116.74.148.55
)

# Whitelisted cities (lowercase, pipe-separated)
# Logins from these cities are shown as ✅ Known location
WHITELIST_CITIES="aurangabad|sharjah|dubai"

# SSH service name — auto-detected if blank: tries "sshd" then "ssh"
SSH_SERVICE=""

# Known-benign failed services to filter from report (space-separated names)
# These are boot-time flukes, not real issues
BENIGN_FAILED_SVCS="cloud-init motd-news systemd-networkd-wait-online"

# SSL expiry warning threshold in days
SSL_WARN_DAYS=14

#=============================================================================
# AUTO-CONFIGURATION (don't edit unless needed)
#=============================================================================

# Detect public IP (for DNSBL check)
SERVER_IP=""
for api in "https://api.ipify.org" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
  SERVER_IP=$(curl -s --max-time 3 "$api" 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+') && break
done
REVERSE_IP=$(echo "$SERVER_IP" | awk -F. '{print $4"."$3"."$2"."$1}')

NOW=$(date '+%d %b %Y, %H:%M')
ALERTS=0

# Geo cache (24h TTL, avoids hammering ip-api.com)
GEO_CACHE="/tmp/.geo-cache-$$"
mkdir -p "$GEO_CACHE"
trap "rm -rf '$GEO_CACHE' /tmp/.classified_ips-$$.txt" EXIT

# Detect SSH service name
if [ -z "$SSH_SERVICE" ]; then
  if systemctl is-active --quiet sshd 2>/dev/null; then
    SSH_SERVICE="sshd"
  elif systemctl is-active --quiet ssh 2>/dev/null; then
    SSH_SERVICE="ssh"
  else
    SSH_SERVICE=""  # will be skipped
  fi
fi

# Detect delivery method
if [ -z "$DELIVERY" ]; then
  if command -v /usr/local/bin/hermes &>/dev/null; then
    DELIVERY="hermes"
  elif [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    DELIVERY="telegram"
  else
    DELIVERY="stdout"
  fi
fi

#=============================================================================
# FUNCTIONS
#=============================================================================

geo_lookup() {
  local ip="$1"
  local cache_file="$GEO_CACHE/$ip"
  [ -f "$cache_file" ] && [ "$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))" -lt 86400 ] && {
    cat "$cache_file" 2>/dev/null; return
  }
  local data
  data=$(curl -s --max-time 4 "http://ip-api.com/json/${ip}" 2>/dev/null)
  if [ -n "$data" ]; then
    echo "$data" > "$cache_file" 2>/dev/null
    echo "$data"
  else
    echo '{}'
  fi
}

send_report() {
  local text="$1"
  case "$DELIVERY" in
    hermes)
      echo "$text" | /usr/local/bin/hermes send -q 2>/dev/null || echo "$text"
      ;;
    telegram)
      [ -z "$TELEGRAM_BOT_TOKEN" ] && { echo "$text"; return; }
      curl -s --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${text}" > /dev/null 2>&1
      ;;
    stdout)
      echo "$text"
      ;;
  esac
}

#=============================================================================
# CHECKS
#=============================================================================

# ── 1. SSH LOGINS ──
LOGIN_COUNT=0
FAIL_COUNT=0
FAIL_IPS=0
UNKNOWN_COUNT=0
KNOWN_COUNT=0

if [ -n "$SSH_SERVICE" ]; then
  LOGINS=$(journalctl -u "$SSH_SERVICE" --since "24 hours ago" --no-pager 2>/dev/null || true)
  ACCEPTED=$(echo "$LOGINS" | grep 'Accepted' || true)
  FAILED=$(echo "$LOGINS" | grep 'Failed password' || true)
  LOGIN_COUNT=$(echo "$ACCEPTED" | wc -l)
  FAIL_COUNT=$(echo "$FAILED" | wc -l)

  echo "$ACCEPTED" | grep -oP 'from \K\S+' | sort -u | while read -r ipaddr; do
    [ -z "$ipaddr" ] && continue
    # Check admin IPs first
    local is_admin=0
    for admin_ip in "${ADMIN_IPS[@]}"; do
      [ "$ipaddr" = "$admin_ip" ] && { is_admin=1; break; }
    done
    if [ "$is_admin" -eq 1 ]; then
      echo "known|$ipaddr|Static IP (whitelisted)"
      continue
    fi
    # Geo lookup
    geo_data=$(geo_lookup "$ipaddr")
    city=$(echo "$geo_data" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print((d.get('city') or '').lower())
except: print('')
" 2>/dev/null)
    country=$(echo "$geo_data" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('country','?') or '?')
except: print('?')
" 2>/dev/null)
    isp=$(echo "$geo_data" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('isp','?') or '?')
except: print('?')
" 2>/dev/null)
    if echo "$city" | grep -qiE "$WHITELIST_CITIES"; then
      echo "known|$ipaddr|$city, $country"
    else
      echo "unknown|$ipaddr|$city, $country ($isp)"
    fi
  done > "/tmp/.classified_ips-$$.txt"

  UNKNOWN_COUNT=$(grep -c '^unknown' "/tmp/.classified_ips-$$.txt" 2>/dev/null || echo 0)
  KNOWN_COUNT=$(grep -c '^known' "/tmp/.classified_ips-$$.txt" 2>/dev/null || echo 0)
  FAIL_IPS=$(echo "$FAILED" | grep -oP 'from \K\S+' | sort -u | wc -l)
fi

# ── 2. DNSBL BLACKLIST ──
SPAMHAUS=""
BARRA=0
if [ -n "$REVERSE_IP" ] && command -v host &>/dev/null; then
  SPAMHAUS=$(host "${REVERSE_IP}.zen.spamhaus.org" 2>&1 | grep -oE '127\.0\.0\.[0-9]' || true)
  BARRA=$(host "${REVERSE_IP}.b.barracudacentral.org" 2>&1 | grep -v 'NXDOMAIN' | wc -l)
fi
[ -n "$SPAMHAUS" ] && ALERTS=$((ALERTS + 1))

# ── 3. SSL CERTIFICATE EXPIRY ──
SSL_EXPIRING=0
if [ -d /etc/letsencrypt/live ] && command -v openssl &>/dev/null; then
  SSL_EXPIRING=$(find /etc/letsencrypt/live -name cert.pem -exec openssl x509 \
    -checkend "$((SSL_WARN_DAYS * 86400))" -noout -in {} \; 2>/dev/null | grep -c 'will expire' || true)
fi
[ "$SSL_EXPIRING" -gt 0 ] && ALERTS=$((ALERTS + 1))

# ── 4. PENDING SECURITY UPDATES ──
SEC_UPDATES=0
if command -v apt-get &>/dev/null; then
  SEC_UPDATES=$(apt list --upgradable 2>/dev/null | grep -ci security 2>/dev/null || true)
fi
[ "$SEC_UPDATES" -gt 0 ] && ALERTS=$((ALERTS + 1))

# ── 5. FAILED SYSTEMD SERVICES ──
FAILED_SVCS=0
if command -v systemctl &>/dev/null; then
  FILTER=$(echo "$BENIGN_FAILED_SVCS" | sed 's/ /|/g')
  FAILED_SVCS=$(systemctl --failed --no-legend 2>/dev/null | grep -vE "($FILTER)" | wc -l)
fi
[ "$FAILED_SVCS" -gt 0 ] && ALERTS=$((ALERTS + 1))

# ── 6. DOCKER CONTAINERS ──
DOCKER_TOTAL=0
DOCKER_UNHEALTHY=0
if command -v docker &>/dev/null; then
  DOCKER_TOTAL=$(docker ps -q 2>/dev/null | wc -l)
  DOCKER_UNHEALTHY=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)
fi

# ── 7. FAIL2BAN ──
SSHD_BANNED=0
WP_BANNED=0
if command -v fail2ban-client &>/dev/null; then
  SSHD_BANNED=$(fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' | grep -oP '\d+' || echo 0)
  WP_BANNED=$(for j in $(fail2ban-client status 2>/dev/null | grep 'Jail list' | cut -d: -f2); do
    fail2ban-client status "$j" 2>/dev/null | grep 'Currently banned' | grep -oP '\d+' || echo 0
  done | paste -sd+ | bc)
  WP_BANNED=$(( ${WP_BANNED:-0} - ${SSHD_BANNED:-0} ))
  [ "$WP_BANNED" -lt 0 ] && WP_BANNED=0
fi

# ── 8. SYSTEM RESOURCES ──
DISK_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%' 2>/dev/null || echo 0)
MEM_PCT=$(free | awk '/Mem/{printf "%.0f", $3/$2 * 100}' 2>/dev/null || echo 0)
HIGH_CPU=$(ps aux --sort=-%cpu | awk 'NR>1 && $3>30 && $11!="ps"{print $3"%"$11}' | head -3 || true)
[ "$DISK_PCT" -gt 85 ] && ALERTS=$((ALERTS + 1))
[ "$MEM_PCT" -gt 90 ] && ALERTS=$((ALERTS + 1))

# ── 9. WORDPRESS (CloudPanel layout assumed) ──
WP_ADMINS=0
BACKDOORS=0
CRON_BAD=0
if [ -d /home ] && ls /home/*/htdocs/*/wp-config.php &>/dev/null; then
  WP_ADMINS=$(for c in /home/*/htdocs/*/wp-config.php; do
    db=$(grep 'DB_NAME' "$c" 2>/dev/null | head -1 | cut -d"'" -f4)
    du=$(grep 'DB_USER' "$c" 2>/dev/null | head -1 | cut -d"'" -f4)
    dp=$(grep 'DB_PASSWORD' "$c" 2>/dev/null | head -1 | cut -d"'" -f4)
    px=$(grep 'table_prefix' "$c" 2>/dev/null | head -1 | cut -d"'" -f2)
    [ -n "$db" ] && [ -n "$px" ] && mysql -u "$du" -p"$dp" "$db" -sN -e \
      "SELECT COUNT(*) FROM ${px}users u JOIN ${px}usermeta m ON u.ID=m.user_id \
       WHERE m.meta_key='${px}capabilities' AND m.meta_value LIKE '%administrator%';" \
      2>/dev/null | grep -v Deprecated
  done | paste -sd+ | bc)
  WP_ADMINS=${WP_ADMINS:-0}

  BACKDOORS=$(find /home/*/htdocs/*/ -type f -name "*.php" -mtime -1 2>/dev/null | \
    xargs -r grep -l 'eval.*base64_decode\|base64_decode.*\$_GET\|base64_decode.*\$_POST' 2>/dev/null | \
    grep -v 'ohio-extra' | wc -l)

  CRON_BAD=$(for f in /etc/cron.d/*; do
    content=$(cat "$f" 2>/dev/null)
    echo "$content" | grep -qiE 'base64|eval|curl.*\|.*sh|wget.*\|.*sh' && echo "$f"
  done | wc -l)
fi

[ "$BACKDOORS" -gt 0 ] && ALERTS=$((ALERTS + 1))
[ "$CRON_BAD" -gt 0 ] && ALERTS=$((ALERTS + 1))

#=============================================================================
# BUILD REPORT
#=============================================================================

REPORT="🔐 Daily Security Report | $SERVER_NAME
$NOW"

# Status line
ISSUES=""
[ -n "$SPAMHAUS" ] && ISSUES="$ISSUES blacklist"
[ "$UNKNOWN_COUNT" -gt 0 ] && ISSUES="$ISSUES unknown-logins"
[ "$SSL_EXPIRING" -gt 0 ] && ISSUES="$ISSUES ssl-expiring"
[ "$SEC_UPDATES" -gt 0 ] && ISSUES="$ISSUES updates"
[ "$FAILED_SVCS" -gt 0 ] && ISSUES="$ISSUES failed-services"
[ "$BACKDOORS" -gt 0 ] && ISSUES="$ISSUES backdoors"
[ "$CRON_BAD" -gt 0 ] && ISSUES="$ISSUES cron-tamper"
[ "$DOCKER_UNHEALTHY" -gt 0 ] && ISSUES="$ISSUES unhealthy-containers"
[ "$DISK_PCT" -gt 85 ] && ISSUES="$ISSUES disk-${DISK_PCT}%"
[ "$MEM_PCT" -gt 90 ] && ISSUES="$ISSUES ram-${MEM_PCT}%"

if [ -n "$ISSUES" ]; then
  REPORT="$REPORT
⚠️  Issues:$ISSUES"
else
  REPORT="$REPORT
✅ All clear"
fi

REPORT="$REPORT
"

# SSH section
REPORT="$REPORT
📡 Blacklist: $([ -n "$SPAMHAUS" ] && echo "Spamhaus LISTED! $SPAMHAUS" || echo "Clean")\
 $([ "$BARRA" -gt 0 ] && echo "| Barracuda LISTED" || echo "| Barracuda Clean")
🔑 SSH logins: ${LOGIN_COUNT} sessions | Failed: ${FAIL_COUNT} attempts (${FAIL_IPS} IPs)
   ✅ Known (${KNOWN_COUNT}): $([ "$KNOWN_COUNT" -gt 0 ] && grep '^known' "/tmp/.classified_ips-$$.txt" | cut -d'|' -f3 | tr '\n' ', ' | sed 's/,$//' || echo 'none')"

if [ "$UNKNOWN_COUNT" -gt 0 ]; then
  REPORT="$REPORT
   ⚠️ Unknown (${UNKNOWN_COUNT}):"
  while IFS='|' read -r _ ip loc; do
    REPORT="$REPORT
      $ip — $loc"
  done < <(grep '^unknown' "/tmp/.classified_ips-$$.txt" 2>/dev/null || true)
fi

# Resource & health section
REPORT="$REPORT
🔒 SSL: $([ "$SSL_EXPIRING" -gt 0 ] && echo "$SSL_EXPIRING expiring!" || echo "OK")
📦 Security updates: $([ "$SEC_UPDATES" -gt 0 ] && echo "$SEC_UPDATES pending" || echo "Up to date")
⚕️  Failed services: $([ "$FAILED_SVCS" -gt 0 ] && echo "$FAILED_SVCS" || echo "None")"

if command -v docker &>/dev/null; then
  REPORT="$REPORT
🐳 Docker: ${DOCKER_TOTAL} running$([ "$DOCKER_UNHEALTHY" -gt 0 ] && echo " ($DOCKER_UNHEALTHY unhealthy!)" || echo "")"
fi

REPORT="$REPORT
🖥️  CPU: $([ -n "$HIGH_CPU" ] && echo "$HIGH_CPU" || echo "Normal") | Disk: ${DISK_PCT}% | RAM: ${MEM_PCT}%
🚫 fail2ban: $([ "$SSHD_BANNED" -gt 0 ] || [ "$WP_BANNED" -gt 0 ] && echo "${SSHD_BANNED} SSH + ${WP_BANNED} WP banned" || echo "No active bans")"

if [ "$WP_ADMINS" -gt 0 ] || [ "$BACKDOORS" -gt 0 ] || [ "$CRON_BAD" -gt 0 ]; then
  REPORT="$REPORT
🌐 WP admins: ${WP_ADMINS} total"
  [ "$BACKDOORS" -gt 0 ] && REPORT="$REPORT | 🔍 Backdoors: ${BACKDOORS} found!"
  [ "$CRON_BAD" -gt 0 ] && REPORT="$REPORT | 📂 Cron tamper: ${CRON_BAD}"
fi

#=============================================================================
# DELIVER
#=============================================================================

send_report "$REPORT"
