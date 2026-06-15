# 9Router ProxyPool

Self-hosted [Squid](https://www.squid-cache.org/) proxy pool for [9Router](https://github.com/decolua/9router) — routes OpenCode Free traffic through your own server IP with anonymous headers stripped and auto-recovery.

Built on top of:
- [yegor256/squid-proxy](https://github.com/yegor256/squid-proxy) — Docker image (anonymous Squid + HTTP Basic auth)
- [decolua/9router](https://github.com/decolua/9router) — the AI gateway this proxy integrates with

---

## ⚠️ For Educational & Research Purposes

This project is intended for **educational and research use only**. Use responsibly:
- Respect the terms of service of any upstream provider you route through this proxy
- Do not use to circumvent authentication, billing, or access controls
- Do not use for any activity prohibited by law in your jurisdiction
- You are solely responsible for how you deploy and operate this software

The authors and contributors assume no liability for misuse.

---

## Prerequisites

Before you start, make sure you have:

- **Docker** + **Docker Compose** installed ([install guide](https://docs.docker.com/get-docker/))
- **9Router** already running (visit `http://localhost:20128` to verify)
- **OpenCode Free** provider visible in your 9Router dashboard

That's it. No Squid expertise required — Docker handles everything.

---

## Quick Start (5 minutes)

```bash
# 1. Get the code
git clone https://github.com/mannnrachman/9router-proxypool.git
cd 9router-proxypool/squid-proxy

# 2. Configure credentials
cp .env.example .env
nano .env            # set your SQUID_PASSWORD
chmod 600 .env

# 3. Start the proxy
docker compose up -d

# 4. Test it works
./test-connection.sh
```

When `test-connection.sh` shows `[PASS]`, proceed to **[Connect to 9Router](#connect-to-9router)** below.

---

## Configuration (`.env`)

Edit `squid-proxy/.env` to customize. All variables:

| Variable | What it does | Example | Notes |
|---|---|---|---|
| `SQUID_USERNAME` | Login username | `opencode` | Pick anything you like |
| `SQUID_PASSWORD` | Login password | (random) | Generate: `openssl rand -base64 18 \| tr -d '/+='` |
| `SQUID_HOST` | Bind interface | `127.0.0.1` | `127.0.0.1` = local only (safe), `0.0.0.0` = expose to network (risky!) |
| `SQUID_PORT` | TCP port | `3128` | Standard Squid port. Change only if conflict |
| `HEALTH_CHECK_URL` | URL used to test proxy | `https://httpbin.org/ip` | Any HTTPS URL returning 200 |

**Beginner tip:** Keep the defaults — they work for 99% of setups. Just change `SQUID_PASSWORD`.

---

## Connect to 9Router

Once your proxy is running and `test-connection.sh` passes, connect it to 9Router in 4 steps.

### Step 1 — Open 9Router Dashboard

Go to `http://localhost:20128/dashboard` in your browser and log in.

### Step 2 — Add the Proxy Pool

1. Open **Proxy Pools** page (URL: `http://localhost:20128/dashboard/proxy-pools`)
2. Click **Add Proxy Pool** → choose **Standard HTTP/HTTPS Proxy**
3. Fill the form:

   | Field | Value |
   |---|---|
   | **Name** | `squid-local` |
   | **Proxy URL** | `http://USERNAME:PASSWORD@HOST:PORT` |
   | **Type** | Standard |
   | **Strict Proxy** | OFF (recommended) |

   Example with values from `.env`:
   ```
   http://opencode:Kx7mP2vQrT9wZ4aB@127.0.0.1:3128
   ```

4. Click **Save**, then click **Test** → expect `HTTP 200`

### Step 3 — Bind to OpenCode Free

1. Open **Providers → OpenCode Free** (URL: `http://localhost:20128/dashboard/providers/opencode`)
2. Scroll to **Proxy Pool** dropdown (under "No authentication required" section)
3. Select `squid-local` → click **Save**

### Step 4 — Verify

Send a test request through 9Router:

```bash
curl -X POST http://localhost:20128/v1/chat/completions \
  -H "Authorization: Bearer YOUR_9ROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "oc/deepseek-v4-flash-free",
    "messages": [{"role": "user", "content": "reply OK"}],
    "stream": false
  }'
```

Expect: HTTP 200 + model reply containing "OK". Done!

> **Strict Proxy** (in Step 2): keep OFF. If Squid goes down, 9Router falls back to direct connection so your work continues. The auto-recovery monitor (below) restarts Squid automatically.

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

## Architecture

```
Your AI Tool (Claude Code, Cursor, etc.)
    ↓ sends request to 9Router
9Router (localhost:20128)
    ↓ looks up OpenCode Free → sees Squid proxy binding
Squid Container (Docker, port 3128)
    ↓ forwards request anonymously (no headers leaked)
opencode.ai (sees your server IP, not 9Router's internals)
```

---

## Day-to-Day Commands

```bash
cd squid-proxy

# Check status
docker compose ps
docker logs squid-proxy --tail 50 -f

# Restart (after editing .env or squid.conf)
docker compose restart

# Stop / Start
docker compose down
docker compose up -d

# Test the proxy
./test-connection.sh

# Manual monitor check
./monitor-squid.sh
```

### Files in this project

```
squid-proxy/
├── .env                  # your credentials (chmod 600, gitignored)
├── .env.example          # template with explanations
├── docker-compose.yml    # compose config (uses ${VAR} from .env)
├── squid.conf            # anonymous hardened config
├── monitor-squid.sh      # auto-recovery cron
└── test-connection.sh    # sanity check script
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

## Test Results (10/10 PASSED)

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
| 9Router "Connection not found" | Wrong URL format | Verify `http://user:pass@host:port` exactly matches `.env` |
| HTTP 407 in dashboard test | Wrong credentials | Re-copy username/password from `.env` |
| `address already in use` | Port 3128 occupied | Change `SQUID_PORT` in `.env` |
| Cannot connect remotely | `SQUID_HOST` is 127.0.0.1 | Change to `0.0.0.0` (and ensure auth is strong!) |

---

## Contributing

Contributions welcome — fork, open issues, submit PRs.

**Areas we'd love help with:**
- Additional relay providers (Vercel, Deno Deploy, Cloudflare Workers)
- Multi-IP rotation patterns
- Documentation translations

Before contributing, please test your changes end-to-end.

---

## License

[MIT License](LICENSE) — same as upstream projects (yegor256/squid-proxy, decolua/9router).

This project is **not affiliated with** Squid Cache, yegor256/squid-proxy, or decolua/9router. All trademarks belong to their respective owners.
