# Squid Proxy (Anonymous HTTP)

Self-hosted [Squid](https://www.squid-cache.org/) proxy with hardened anonymity — strips all identifying headers (`Via`, `X-Forwarded-For`, `X-Squid-Error`, etc.) and requires HTTP Basic Auth.

> **When to use Squid vs WARP?** Squid only strips headers — your server IP is still visible to opencode.ai. If you want to **change** the visible IP, use [Cloudflare WARP](./cloudflare-warp.md) instead. Squid is for cases where you only need anonymity (no proxy signature leak) plus authentication.

---

## How It Works

```
9Router (:20128)
    ↓ routes OpenCode Free → squid-local pool
Squid Container (Docker, port 3128)
    ↓ strips Via/XFF/X-Squid-Error headers
    ↓ requires HTTP Basic Auth
opencode.ai (sees your server IP, but no proxy signature)
```

---

## Prerequisites

- Docker + Docker Compose
- 9Router running (verify at `http://10.0.0.1:20128/dashboard`)
- OpenCode Free provider visible in dashboard

---

## Quick Start

```bash
cd 9router-proxypool/squid-proxy

# 1. Configure credentials
cp .env.example .env
nano .env          # set SQUID_PASSWORD
chmod 600 .env

# 2. Start the proxy
docker compose up -d

# 3. Test it works
./test-connection.sh
```

When `test-connection.sh` shows `[PASS]`, proceed to **[Connect to 9Router](#connect-to-9router)** below.

---

## Configuration (`.env`)

| Variable | What it does | Example | Notes |
|---|---|---|---|
| `SQUID_USERNAME` | Login username | `opencode` | Pick anything you like |
| `SQUID_PASSWORD` | Login password | (random) | Generate: `openssl rand -base64 18 \| tr -d '/+='` |
| `SQUID_HOST` | Bind interface | `127.0.0.1` | `127.0.0.1` = local only (safe), `0.0.0.0` = expose to network (risky!) |
| `SQUID_PORT` | TCP port | `3128` | Standard Squid port |
| `HEALTH_CHECK_URL` | URL used to test proxy | `https://httpbin.org/ip` | Any HTTPS URL returning 200 |

---

## Connect to 9Router

### Option A: Dashboard UI

1. Open **Proxy Pools** → Add Proxy Pool → **Standard HTTP/HTTPS**
2. Fill:

   | Field | Value |
   |---|---|
   | **Name** | `squid-local` |
   | **Proxy URL** | `http://USERNAME:PASSWORD@127.0.0.1:3128` |
   | **Type** | Standard |
   | **Strict Proxy** | OFF (recommended) |

3. Save → Test → expect `HTTP 200`
4. **Providers → OpenCode Free** → Proxy Pool dropdown → `squid-local` → Save

> **Strict Proxy OFF** recommended: if Squid goes down, 9Router falls back to direct connection so your work continues.

### Option B: 9Router API

```bash
# 1. Login
curl -s -c /tmp/9r-cookies.txt -X POST http://10.0.0.1:20128/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"password":"YOUR_9ROUTER_PASSWORD"}'

# 2. Create pool
POOL_ID=$(curl -s -b /tmp/9r-cookies.txt -X POST http://10.0.0.1:20128/api/proxy-pools \
  -H "Content-Type: application/json" \
  -d '{
    "name": "squid-local",
    "type": "standard",
    "proxyUrl": "http://USERNAME:PASSWORD@127.0.0.1:3128",
    "isActive": true
  }' | python3 -c "import json,sys; print(json.load(sys.stdin)['proxyPool']['id'])")

# 3. Test pool
curl -s -b /tmp/9r-cookies.txt -X POST \
  "http://10.0.0.1:20128/api/proxy-pools/${POOL_ID}/test"

# 4. Bind to OpenCode Free
curl -s -b /tmp/9r-cookies.txt -X PATCH http://10.0.0.1:20128/api/settings \
  -H "Content-Type: application/json" \
  -d "{\"providerStrategies\":{\"opencode\":{\"proxyPoolId\":\"${POOL_ID}\"}}}"
```

---

## Auto-Recovery (Recommended)

Install the monitor cron so the proxy self-heals on crash:

```bash
crontab -e
# Add this line (adjust the path):
*/2 * * * * /path/to/9router-proxypool/squid-proxy/monitor-squid.sh >> /var/log/squid-monitor.log 2>&1
```

The monitor runs every 2 minutes and:
- Restarts the Squid container if it crashes or disappears
- Restarts 9Router service if down
- Verifies the proxy binding still exists

Logs go to `/var/log/squid-monitor.log`.

---

## Day-to-Day Commands

```bash
cd squid-proxy

docker compose ps                       # status
docker logs squid-proxy --tail 50 -f    # logs
docker compose restart                  # restart
docker compose down                     # stop
docker compose up -d                    # start

./test-connection.sh                    # test proxy
./monitor-squid.sh                      # manual monitor check
```

---

## Files

```
squid-proxy/
├── .env                # credentials (chmod 600, gitignored)
├── .env.example        # template
├── docker-compose.yml  # compose config (uses ${VAR} from .env)
├── squid.conf          # anonymous hardened config
├── monitor-squid.sh    # auto-recovery cron
└── test-connection.sh  # sanity check script
```

---

## Hardening Details

Beyond the base `yegor256/squid-proxy` image, this setup strips all identifying headers:

| Header | Default Squid | This Setup |
|---|---|---|
| `Via` (success & error) | leaked | stripped ✓ |
| `X-Squid-Error` | leaked | stripped ✓ |
| `X-Cache`, `Cache-Status` | leaked | stripped ✓ |
| `X-Forwarded-For` | leaked | stripped ✓ |
| Squid version | exposed | hidden ✓ |

Implemented in `squid.conf` via `via off`, `httpd_suppress_version_string on`, and `reply_header_access` rules.

**Authentication is required** — all requests need HTTP Basic Auth or get 407.

---

## Test Results

| Test | Result |
|---|---|
| Functional chat request | ✅ HTTP 200 |
| Network capture (proxy used) | ✅ Verified |
| Performance overhead | ✅ ~70ms |
| 5 parallel requests | ✅ All 200, CPU 0.01% |
| Auth (407 on bad creds) | ✅ Verified |
| Streaming SSE | ✅ 160 chunks |
| Auto-recovery on `docker rm` | ✅ Recreated in 1s |
| Long context (5KB) | ✅ 3.5s |
| Provider isolation | ✅ Other providers direct |
| Config persistence | ✅ Survives restart |

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `test-connection.sh` returns FAIL | Squid container not running | `docker compose up -d` |
| 9Router "Connection not found" | Wrong URL format | Verify `http://user:pass@host:port` matches `.env` |
| HTTP 407 in dashboard test | Wrong credentials | Re-copy username/password from `.env` |
| `address already in use` | Port 3128 occupied | Change `SQUID_PORT` in `.env` |
| Cannot connect remotely | `SQUID_HOST` is 127.0.0.1 | Change to `0.0.0.0` (and ensure auth is strong!) |
