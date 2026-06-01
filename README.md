# 🗼 VPS WatchTower

**Daily server security report — delivered to your Telegram.**

One script. Drop it on any Linux server. Get a morning security digest that audits SSH logins with geo-location, tracks failed attempts, checks blacklists, monitors SSL expiry, and keeps an eye on system health.

```
🔐 VPS WatchTower | My VPS
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

> **Everything you need to monitor your server — delivered to your Telegram every morning.**

### 🔐 SSH Security & Geo-Audit
- **Geo-login tracking** — Know your cities (Aurangabad, Sharjah, Dubai, etc.). Logins from anywhere else are flagged with IP, city, country & ISP
- **Failed login monitoring** — See how many brute-force attempts hit your server daily and from how many unique IPs
- **Admin IP whitelist** — Static IPs skip geo-lookup entirely, always shown as known

### 🚫 DNSBL Blacklist Check
- **Spamhaus & Barracuda** — Checks if your server is blacklisted and being abused as a spam relay
- Instant alert if your IP is listed so you can act fast

### 📲 Telegram Delivery
- **Daily digest on your phone** — Wake up to a clean security report every morning
- **Two delivery modes** — Hermes CLI (preferred) or direct Telegram Bot API (no extra software needed)
- **Zero infrastructure** — No databases, no dashboard, no web app needed

### 🌐 WordPress Security
- **Backdoor scan** — Scans for PHP files containing `base64_decode` + `$_GET`/`$_POST` — the classic webshell signature
- **Admin account audit** — Counts admin users across all your WordPress sites
- **Cron tamper detection** — Flags suspicious cron entries (base64, eval, curl|sh patterns)

### 🐳 Docker Container Health
- **Running container count** — See how many containers are active
- **Unhealthy container alerts** — Flags containers with failing health checks

### 🔒 SSL Certificate Monitoring
- **Expiry warnings** — Shows how many certificates expire within 14 days
- Catches expiring certs before your sites go down

### ⚕️ System Health
- **Failed systemd services** — Catches crashed or misconfigured services
- **Disk space usage** — Alerts when disk exceeds 85%
- **RAM usage** — Alerts when memory exceeds 90%
- **High CPU processes** — Shows any process using >30% CPU
- **Pending security updates** — Counts available `apt` security patches
- **fail2ban stats** — Active ban counts for SSH and other jails

## Included Scripts

| File | Purpose |
|------|---------|
| `watchtower.sh` | **Daily security report** — runs on cron, gives you a morning digest |
| `ssh-login-alert.sh` | **Real-time SSH login alert** — fires on every SSH login, sends geo-location immediately |

### `ssh-login-alert.sh` Setup

Sends an instant Telegram notification whenever someone SSHs into your server:

```bash
# 1. Download
curl -sL https://raw.githubusercontent.com/MaxBuzz-dev/VPS-WatchTower/main/ssh-login-alert.sh \
  -o /root/ssh-login-alert.sh
chmod +x /root/ssh-login-alert.sh

# 2. Edit the top of the file — set BOT_TOKEN, CHAT_ID, and SERVER_NAME

# 3. Hook into SSH
echo '/root/ssh-login-alert.sh "$1"' >> /etc/ssh/sshrc
chmod +x /etc/ssh/sshrc
```

Now every SSH login sends a message like:
```
🔑 SSH Login - root
🖥 My Server
IP: 203.0.113.42
📍 Bangkok, Thailand
🏢 Some ISP
⏰ 01 Jun 2026, 08:00 UTC
```

## Quick Start

### 1. Download the daily report

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
🔐 VPS WatchTower | My VPS
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
🔐 VPS WatchTower | My VPS
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
