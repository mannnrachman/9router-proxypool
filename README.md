# 9Router ProxyPool

Self-hosted proxy pools for [9Router](https://github.com/decolua/9router) — route OpenCode Free traffic through your own proxy with auto-recovery.

## Two Proxy Options

| Option | What it does | Best for |
|---|---|---|
| **[Cloudflare WARP](./docs/cloudflare-warp.md)** ⭐ | SOCKS5 proxy with **IP rotation** — routes through Cloudflare's network with multiple rotating IPs | Hiding your real server IP + distribute traffic across IPs |
| **[Squid Proxy](./docs/squid-proxy.md)** | Anonymous HTTP proxy that strips identifying headers (`Via`, `X-Forwarded-For (XFF)`, etc.) + auth | Anonymity without IP change |

> **New here?** Start with [Cloudflare WARP](./docs/cloudflare-warp.md) — it's the recommended option for most users.

---

## ⚠️ For Educational & Research Purposes

This project is intended for **educational and research use only**:
- Respect the terms of service of any upstream provider you route through
- Do not use to circumvent authentication, billing, or access controls
- You are solely responsible for how you deploy and operate this software

The authors and contributors assume no liability for misuse.

---

## Prerequisites

- **Docker** + **Docker Compose** ([install guide](https://docs.docker.com/get-docker/))
- **9Router** already running (default: `http://10.0.0.1:20128/dashboard`)
- **OpenCode Free** provider visible in your 9Router dashboard

---

## Architecture

```
Your AI Tool (Claude Code, Cursor, etc.)
    ↓ sends request to 9Router
9Router (:20128)
    ↓ looks up OpenCode Free → sees proxy binding
Proxy Docker Container (WARP :10800 / Squid :3128)
    ↓ forwards traffic
opencode.ai
```

---

## Quick Links

- 📘 [Cloudflare WARP Setup →](./docs/cloudflare-warp.md)
- 📘 [Squid Proxy Setup →](./docs/squid-proxy.md)

---

## Project Structure

```
9router-proxypool/
├── README.md
├── docs/
│   ├── cloudflare-warp.md   # WARP SOCKS5 setup guide
│   └── squid-proxy.md       # Squid HTTP setup guide
├── warp-proxy/              # WARP Docker setup
│   ├── docker-compose.yml
│   ├── .env.example
│   └── test-warp.sh
└── squid-proxy/             # Squid Docker setup
    ├── docker-compose.yml
    ├── squid.conf
    ├── .env.example
    ├── monitor-squid.sh
    └── test-connection.sh
```

---

## Built On

- [dublok/cloudflare-warp](https://hub.docker.com/r/dublok/cloudflare-warp) — Docker image used by this project for Cloudflare WARP
- [ErcinDedeoglu/cloudflare-warp](https://github.com/ErcinDedeoglu/cloudflare-warp) — upstream Cloudflare WARP implementation
- [yegor256/squid-proxy](https://github.com/yegor256/squid-proxy) — anonymous Squid + HTTP Basic auth
- [decolua/9router](https://github.com/decolua/9router) — the AI gateway this proxy integrates with

---

## Contributing

Contributions welcome — fork, open issues, submit PRs.

**Areas we'd love help with:**
- Cloudflare Workers relay provider (best fit for AI API proxy — zero cold start, native outbound TCP, cheapest at scale)
- Deno Deploy relay provider
- Documentation translations

> **Note on Vercel:** Not recommended for relay use case — 30x costlier than Cloudflare Workers at volume, higher cold starts, no native outbound TCP on Edge runtime.

Before contributing, please test your changes end-to-end.

---

## License

[MIT License](LICENSE) — same as upstream projects.

This project is **not affiliated with** Cloudflare, Squid Cache, yegor256/squid-proxy, or decolua/9router. All trademarks belong to their respective owners.
