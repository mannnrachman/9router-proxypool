# Cloudflare WARP Proxy

SOCKS5 proxy using [Cloudflare WARP](https://developers.cloudflare.com/warp-client/) with **IP rotation** — routes OpenCode Free traffic through Cloudflare's network with multiple rotating IPs.

Built on [dublok/cloudflare-warp](https://hub.docker.com/r/dublok/cloudflare-warp) (upstream: [ErcinDedeoglu/cloudflare-warp](https://github.com/ErcinDedeoglu/cloudflare-warp)).

> **Why WARP over Squid?** Squid only strips headers — your server IP is still visible. WARP routes traffic through Cloudflare, so opencode.ai sees a Cloudflare IP (e.g., `104.x.x.x`), not your real server IP. With multi-instance, each request exits through a different Cloudflare IP.

---

## How It Works

```
9Router (:20128)
    ↓ routes OpenCode Free → warp-local pool
WARP Docker Container (:10800, SOCKS5 + auth)
    ↓ GOST round-robin across N instances
    ├─ Instance 1 (IP: 104.28.x.1)
    ├─ Instance 2 (IP: 104.28.x.2)
    ├─ Instance 3 (IP: 104.28.x.3)
    ├─ Instance 4 (IP: 104.28.x.4)
    └─ Instance 5 (IP: 104.28.x.5)
    ↓ encrypted tunnel each
Cloudflare Network (SG/datacenter)
    ↓
opencode.ai (sees rotating Cloudflare IPs, not your server)
```

**IP Rotation:** Each WARP instance gets a unique Cloudflare IP. GOST round-robins requests across all instances, so consecutive requests exit through different IPs. If an instance fails, GOST skips it after 3 failures and retries after 30s.

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
| `WARP_INSTANCES` | Number of WARP instances | `10` | Each registers independently with Cloudflare. RAM ~70-100MB per instance |
| `WARP_LICENSE_KEY` | WARP+ license (optional) | `xxxx-xxxx-xxxx-xxxx` | Free tier works without it |
| `WARP_HOST` | Host bind | `127.0.0.1` | Localhost only (secure) |
| `WARP_PORT` | Host port | `10800` | Container internal port is 1080 |

**Security defaults:**
- Binds to `127.0.0.1` (localhost only — not exposed to internet)
- Requires SOCKS5 authentication (no open proxy)
- Rate limit disabled (`PROXY_MAX_CONN=0`, `PROXY_MAX_RPS=0`) — safe since 9Router is on localhost
- WireGuard/SSH on host unaffected

### Tuning IP Rotation

Edit `WARP_INSTANCES` in `.env`:

| Value | RAM | Use case |
|---|---|---|
| `1` | ~100MB | No rotation (single IP) |
| `3` | ~300MB | Light rotation, low traffic |
| `5` | ~500MB | Balanced for personal use |
| `10` | ~700MB-1GB | **Default** — heavy rotation, parallel requests |
| `15-20` | ~1.5-2GB | Max rotation (diminishing returns on unique IPs) |

**How to add or remove instances:**

```bash
cd 9router-proxypool/warp-proxy

# 1. Edit .env
nano .env
# Change: WARP_INSTANCES=10  (or any number you want)

# 2. Restart container (required - instances spawn at startup)
docker compose down && docker compose up -d

# 3. Wait ~30s for all instances to register with Cloudflare
sleep 30

# 4. Verify
docker exec warp-proxy bash -c "ls /var/lib/cloudflare-warp/ | grep -c instance"
# Expected output: 10 (or your configured number)

# 5. Test rotation
./test-warp.sh
```

> **Important:** You MUST run `docker compose down && docker compose up -d` (not just `restart`) when changing `WARP_INSTANCES`. The instance count is read at container startup; a plain restart reuses the old config.

### Understanding Unique IP Count

Cloudflare WARP free tier shares a limited IP pool across all users. Even with 10 instances, you may see only 3-5 unique IPs because:

- Each instance requests an IP from Cloudflare's pool on registration
- Cloudflare reuses IPs across instances in the same datacenter
- The pool is regional (e.g., Singapore datacenter has fewer IPs than US)

**What more instances DO give you:**
- ✅ Higher throughput (more parallel connections)
- ✅ Better per-IP load distribution
- ✅ Faster failover when one instance dies

**What more instances DON'T give you:**
- ❌ More unique IPs beyond Cloudflare's pool limit
- ❌ Different geographic regions (all instances use nearest PoP)

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

### Verify IP Rotation

```bash
# Send 10 requests, see different Cloudflare IPs
for i in {1..10}; do
  curl -s --proxy socks5://opencode:PASSWORD@127.0.0.1:10800 https://ifconfig.me
  echo ""
done
```

You should see 2-5 different `104.x.x.x` IPs (depending on `WARP_INSTANCES`).

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
| All requests same IP | Instances still warming up | Wait 30s, re-run test |
| Fewer unique IPs than instances | Some instances still connecting | Normal during startup; re-check after 1 min |
| "User was rejected" | Wrong credentials | Re-check `WARP_PROXY_USER`/`PASS` in `.env` |
| `address already in use` | Port 10800 occupied | Change `WARP_PORT` in `.env` |
| 9Router test fails | Wrong URL or 9Router can't reach localhost | Verify 9Router binds to `10.0.0.1` and proxy is `127.0.0.1:10800` |
| High RAM usage | Too many instances | Reduce `WARP_INSTANCES` in `.env` |

---

## Security Notes

- **Not affiliated with Cloudflare.** WARP is a Cloudflare product; this project only wraps the official client in Docker.
- Free tier has fair-use limits. Heavy abuse may get the WARP account rate-limited.
- The visible IP is shared across many Cloudflare WARP users — not a dedicated IP.
