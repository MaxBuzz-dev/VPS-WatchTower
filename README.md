# 🗼 VPS Watchtower

**Daily server security report — delivered to your Telegram.**

One script. Drop it on any Linux server. Get a morning security digest that audits SSH logins with geo-location, tracks failed attempts, checks blacklists, monitors SSL expiry, and keeps an eye on system health.

```
🔐 VPS Watchtower | My VPS
31 May 2026, 08:00
✅ All clear

📡 Blacklist: Clean
🔑 SSH logins: 15 sessions | Failed: 342 attempts (87 IPs)
   ✅ Known (2): Aurangabad, India
⚕️  Failed services: None
🔒 SSL: OK
📦 Security updates: Up to date
🖥️  CPU: Normal | Disk: 62% | RAM: 45%
```

## Features

| Check | What it catches |
|---|---|
| SSH geo-login audit | Knows your cities (Aurangabad, Dubai, etc.) — flags everything else |
| Failed login tracking | See brute-force volume per day |
| DNSBL blacklist check | Spamhaus & Barracuda — is your server being abused? |
| SSL cert expiry | Warns when certs have <14 days left |
| Security updates | `apt` security patch count |
| Failed systemd services | Catches crashed services |
| Docker health | Running container count + unhealthy containers |
| WordPress admin audit | Counts admin users across all WP sites |
| Backdoor scan | PHP files with `base64_decode` + `$_GET`/`$_POST` |
| fail2ban stats | SSH + jail ban counts |
| Cron tamper detection | Suspicious cron jobs (base64, eval, curl\|sh) |
| System resources | Disk %, RAM %, high CPU processes |

## Quick Start

### 1. Download

```bash
curl -sL https://raw.githubusercontent.com/MaxBuzz-dev/VPS-WatchTower/main/watchtower.sh \
  -o /usr/local/bin/watchtower.sh
chmod +x /usr/local/bin/watchtower.sh
```

### 2. Configure

Edit the **CONFIGURATION** block at the top:

```bash
SERVER_NAME="My Production Server"
TELEGRAM_BOT_TOKEN="1234....."   # from @BotFather
TELEGRAM_CHAT_ID="123456789"                # your Telegram ID
ADMIN_IPS=(60.254.60.25 116.74.148.55)      # your known IPs
WHITELIST_CITIES="aurangabad|sharjah|dubai" # your cities
```

### 3. Schedule

Runs daily at 8AM IST (2:30 UTC):

```bash
echo "30 2 * * * root /usr/local/bin/watchtower.sh" \
  > /etc/cron.d/vps-watchtower
```

### 4. Test

```bash
bash /usr/local/bin/watchtower.sh
```

## Requirements

**Required:** `bash`, `curl`, `python3`

**Optional (auto-detected, gracefully skipped if missing):** fail2ban, docker, openssl, mysql

**Delivery modes (auto-detected):**
1. **Hermes CLI** — preferred if installed (`/usr/local/bin/hermes`)
2. **Telegram Bot API** — direct curl (no extra software)
3. **stdout** — prints to terminal (for testing or email piping)

## Example Outputs

**Clean server:**
```
🔐 VPS Watchtower | My VPS
✅ All clear

📡 Blacklist: Clean
🔑 SSH logins: 3 sessions | Failed: 12 attempts (6 IPs)
   ✅ Known (2): Aurangabad, India
⚕️  Failed services: None
🔒 SSL: OK
📦 Security updates: Up to date
🖥️  CPU: Normal | Disk: 45% | RAM: 30%
```

**Server with issues:**
```
🔐 VPS Watchtower | My VPS
⚠️  Issues: unknown-logins updates failed-services

🔑 SSH logins: 28 sessions | Failed: 891 attempts (203 IPs)
   ✅ Known (1): Aurangabad, India
   ⚠️ Unknown (1): 203.0.113.42 — Bangkok, Thailand (ISP)
⚕️  Failed services: 1 (nginx.service)
📦 Security updates: 14 pending
🖥️  CPU: Normal | Disk: 82% | RAM: 76%
```

## Geo-Location Notes

- Uses [ip-api.com](http://ip-api.com) (free tier: 45 req/min, no key needed)
- Results are cached for 24 hours per IP
- For daily reports on personal servers, you'll never hit rate limits
- If ip-api.com is down, geo data shows as "?"

## License

MIT — do whatever you want with it. Attribution appreciated but not required.
