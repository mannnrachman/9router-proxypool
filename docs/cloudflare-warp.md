# Cloudflare WARP Proxy

SOCKS5 proxy using [Cloudflare WARP](https://developers.cloudflare.com/warp-client/) — **changes your visible IP** to Cloudflare's network. Recommended when you want OpenCode Free to see a Cloudflare IP instead of your server's IP.

> **Why WARP over Squid?** Squid only strips headers — your server IP is still visible. WARP actually routes traffic through Cloudflare, so opencode.ai sees a Cloudflare IP (e.g., `104.x.x.x`), not your real server IP.

---

## How It Works

```
9Router (:20128)
    ↓ routes OpenCode Free → warp-local pool
WARP Docker Container (:10800, SOCKS5 + auth)
    ↓ encrypted tunnel
Cloudflare Network (SG/datacenter, IP: 104.x.x.x)
    ↓
opencode.ai (sees Cloudflare IP, not your server)
```

**Key safety feature:** WARP runs **inside a Docker container** with isolated networking. It does **not** interfere with:
- Your WireGuard SSH connection
- Host routing tables
- Other services on the host

---

## Prerequisites

- Docker + Docker Compose
- 9Router running (verify at `http://10.0.0.1:20128/dashboard`)
- OpenCode Free provider visible in dashboard

---

## Quick Start

```bash
cd 9router-proxypool/warp-proxy

# 1. Configure credentials
cp .env.example .env
nano .env          # set WARP_PROXY_USER and WARP_PROXY_PASS
chmod 600 .env

# 2. Start WARP
docker compose up -d

# 3. Test it works
./test-warp.sh
```

When `test-warp.sh` shows `[PASS]`, proceed to **[Connect to 9Router](#connect-to-9router)** below.

---

## Configuration (`.env`)

| Variable | What it does | Example | Notes |
|---|---|---|---|
| `WARP_PROXY_USER` | SOCKS5 auth username | `opencode` | Required — rejects unauthenticated use |
| `WARP_PROXY_PASS` | SOCKS5 auth password | (random) | Generate: `openssl rand -base64 18 \| tr -d '/+='` |
| `WARP_LICENSE_KEY` | WARP+ license (optional) | `xxxx-xxxx-xxxx-xxxx` | Free tier works without it |
| `WARP_HOST` | Host bind | `127.0.0.1` | Localhost only (secure) |
| `WARP_PORT` | Host port | `10800` | Container internal port is 1080 |

**Security defaults:**
- Binds to `127.0.0.1` (localhost only — not exposed to internet)
- Requires SOCKS5 authentication (no open proxy)
- WireGuard/SSH on host unaffected

---

## Connect to 9Router

### Option A: Dashboard UI

1. Open **Proxy Pools** → Add Proxy Pool → **SOCKS5**
2. Fill:

   | Field | Value |
   |---|---|
   | **Name** | `warp-local` |
   | **Proxy URL** | `socks5://USERNAME:PASSWORD@127.0.0.1:10800` |
   | **Type** | SOCKS5 |

   Replace `USERNAME:PASSWORD` with values from `.env`.

3. Save → Test → expect success
4. **Providers → OpenCode Free** → Proxy Pool dropdown → `warp-local` → Save

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
    "name": "warp-local",
    "type": "socks5",
    "proxyUrl": "socks5://USERNAME:PASSWORD@127.0.0.1:10800",
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

## Verify End-to-End

```bash
curl -X POST http://10.0.0.1:20128/v1/chat/completions \
  -H "Authorization: Bearer YOUR_9ROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "oc/deepseek-v4-flash-free",
    "messages": [{"role": "user", "content": "reply OK"}],
    "stream": false
  }'
```

Expect: HTTP 200 + reply containing "OK".

---

## Day-to-Day Commands

```bash
cd warp-proxy

docker compose ps                    # status
docker logs warp-proxy --tail 50 -f  # logs
docker compose restart               # restart
docker compose down                  # stop
docker compose up -d                 # start

./test-warp.sh                       # test proxy
```

---

## Files

```
warp-proxy/
├── .env                # credentials (chmod 600, gitignored)
├── .env.example        # template
├── docker-compose.yml  # compose config (127.0.0.1 bind + auth)
├── test-warp.sh        # proxy test script
└── data/               # WARP registration state (gitignored)
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `test-warp.sh` shows FAIL | Container not running | `docker compose up -d` |
| `warp=off` in test | WARP daemon not connected | `docker compose restart`, wait 10s |
| "User was rejected" | Wrong credentials | Re-check `WARP_PROXY_USER`/`PASS` in `.env` |
| `address already in use` | Port 10800 occupied | Change `WARP_PORT` in `.env` |
| 9Router test fails | Wrong URL or 9Router can't reach localhost | Verify 9Router binds to `10.0.0.1` and proxy is `127.0.0.1:10800` |

---

## Security Notes

- **Not affiliated with Cloudflare.** WARP is a Cloudflare product; this project only wraps the official client in Docker.
- Free tier has fair-use limits. Heavy abuse may get the WARP account rate-limited.
- The visible IP is shared across many Cloudflare WARP users — not a dedicated IP.
