# 9Router ProxyPool

Self-hosted [Squid](https://www.squid-cache.org/) proxy pool configuration for [9Router](https://github.com/decolua/9router) — routes OpenCode Free traffic through your own server IP with anonymous headers stripped and auto-recovery.

Built on top of:
- [yegor256/squid-proxy](https://github.com/yegor256/squid-proxy) — Docker image for anonymous Squid with HTTP Basic auth
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

## Architecture

```
9Router (localhost:20128)
    ↓ HTTP POST /v1/chat/completions (model oc/*)
Provider OpenCode Free → resolve proxy from providerStrategies
    ↓ Proxy URL: http://${SQUID_USERNAME}:${SQUID_PASSWORD}@${SQUID_HOST}:${SQUID_PORT}
Squid Container (Docker, yegor256/squid-proxy:latest)
    ↓ Custom config: anonymous + reply_header stripped
opencode.ai (sees server IP, no Squid headers leaked)
```

---

## Quick Start

```bash
cd squid-proxy

# 1. Copy template and edit credentials
cp .env.example .env
nano .env

# 2. Restrict permissions (file contains secrets)
chmod 600 .env

# 3. Start the proxy
docker compose up -d

# 4. Test it works
./test-connection.sh
```

Then bind the proxy in your 9Router dashboard:
- **URL:** `http://USERNAME:PASSWORD@HOST:PORT` (use the values you set in `.env`)
- **Type:** Standard HTTP proxy

---

## Configuration (`.env`)

All settings live in `squid-proxy/.env`. Copy `.env.example` and fill in your values:

| Variable | What it does | Example | Notes |
|---|---|---|---|
| `SQUID_USERNAME` | Login username for the proxy | `opencode` | Pick anything you like |
| `SQUID_PASSWORD` | Login password for the proxy | (random) | Generate with: `openssl rand -base64 18 \| tr -d '/+='` |
| `SQUID_HOST` | Network interface to bind | `127.0.0.1` | Use `127.0.0.1` for local-only, `0.0.0.0` to expose (risky!) |
| `SQUID_PORT` | TCP port | `3128` | Standard Squid port. Change only if conflict |
| `HEALTH_CHECK_URL` | URL monitor uses to test proxy | `https://httpbin.org/ip` | Any HTTPS URL returning 200 |

### Example filled `.env`

```bash
SQUID_USERNAME=opencode
SQUID_PASSWORD=Kx7mP2vQrT9wZ4aB
SQUID_HOST=127.0.0.1
SQUID_PORT=3128
HEALTH_CHECK_URL=https://httpbin.org/ip
```

> **Beginner tip:** Start with the example values above (but use your own password!). The defaults work for 99% of single-machine setups.

---

## Files

```
squid-proxy/
├── .env                  # your credentials (chmod 600, gitignored)
├── .env.example          # template with explanations
├── docker-compose.yml    # compose config (uses ${VAR} from .env)
├── squid.conf            # anonymous hardened config
├── monitor-squid.sh      # auto-recovery cron (runs every 2 min)
└── test-connection.sh    # sanity check script
```

---

## Day-to-Day Commands

```bash
cd squid-proxy

# Status
docker compose ps
docker logs squid-proxy --tail 50 -f

# Restart
docker compose restart

# Stop / Start
docker compose down
docker compose up -d

# Edit config
nano .env            # change credentials
nano squid.conf      # change proxy behavior
docker compose up -d # apply changes

# Manual monitor check
./monitor-squid.sh

# Test proxy works
./test-connection.sh
```

### Auto-Recovery (Cron)

Install the monitor cron to auto-restart on failure:

```bash
crontab -e
# Add this line:
*/2 * * * * /path/to/9router-proxypool/squid-proxy/monitor-squid.sh >> /var/log/squid-monitor.log 2>&1
```

The monitor checks every 2 minutes:
1. Container running
2. Health status
3. Proxy responds with HTTP 200
4. 9Router binding intact
5. 9Router service active

If any check fails, it auto-recovers.

---

## Hardening Details

This setup includes security hardening beyond the base `yegor256/squid-proxy` image:

### Anonymous Headers (Stripped)

| Header | Default Squid | This Setup |
|---|---|---|
| `Via` (success) | leaked | stripped ✓ |
| `Via` (error 407) | leaked | stripped ✓ |
| `X-Squid-Error` | leaked | stripped ✓ |
| `X-Cache`, `Cache-Status` | leaked | stripped ✓ |
| `X-Forwarded-For` | leaked | stripped ✓ |
| Squid version | exposed | hidden ✓ |

Implemented in `squid.conf` via:
- `via off`
- `httpd_suppress_version_string on`
- `visible_hostname proxy`
- `reply_header_access` rules for all leak-prone headers

### Authentication Required

All proxy requests require HTTP Basic Auth. Wrong credentials → 407 Proxy Authentication Required.

---

## Test Results (10/10 PASSED)

| Test | Status |
|---|---|
| Functional chat request | ✅ HTTP 200 |
| Network tcpdump (proxy used) | ✅ Verified |
| Performance overhead | ✅ ~70ms |
| 5 parallel requests | ✅ All 200, CPU 0.01% |
| Auth (407 on bad creds) | ✅ Verified |
| Streaming SSE | ✅ 160 chunks |
| Auto-recovery on `docker rm` | ✅ Recreated in 1s |
| Long context (5KB) | ✅ 3.5s |
| Provider isolation | ✅ Other providers direct |
| Config persistence | ✅ Survives restart |

---

## Contributing

Contributions are welcome! This is an open educational project — feel free to:

1. **Fork** the repository
2. **Open issues** for bugs, suggestions, or improvements
3. **Submit pull requests** for new features or fixes

### Areas we'd love help with:
- Additional relay provider configurations (Vercel, Deno Deploy, Cloudflare Workers)
- Multi-IP rotation patterns
- Improved monitoring / alerting
- Documentation translations

Before contributing, please read the existing files and ensure your changes are tested end-to-end.

---

## License

[MIT License](LICENSE) — same as upstream projects (yegor256/squid-proxy, decolua/9router).

This project is **not affiliated with** Squid Cache, yegor256/squid-proxy, or decolua/9router. All trademarks belong to their respective owners.
