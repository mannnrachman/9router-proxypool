#!/bin/bash
# Test Cloudflare WARP proxy connection
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Load .env if present
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

# Defaults
WARP_HOST="${WARP_HOST:-127.0.0.1}"
WARP_PORT="${WARP_PORT:-1080}"
WARP_HEALTH_URL="${WARP_HEALTH_URL:-https://cloudflare.com/cdn-cgi/trace}"
WARP_PROXY_USER="${WARP_PROXY_USER:-}"
WARP_PROXY_PASS="${WARP_PROXY_PASS:-}"

echo "=========================================="
echo " Cloudflare WARP Connection Test"
echo "=========================================="
echo ""

echo "=== Test 1: Direct connection (no proxy) ==="
DIRECT_OUTPUT=$(curl -s --max-time 10 "$WARP_HEALTH_URL" 2>/dev/null)
DIRECT_WARP=$(echo "$DIRECT_OUTPUT" | grep -o "^warp=.*" || echo "warp=off")
echo "  Direct: ${DIRECT_WARP}"

echo ""
echo "=== Test 2: Via WARP proxy ==="
if [ -n "$WARP_PROXY_USER" ] && [ -n "$WARP_PROXY_PASS" ]; then
    PROXY_URL="socks5://${WARP_PROXY_USER}:${WARP_PROXY_PASS}@${WARP_HOST}:${WARP_PORT}"
else
    PROXY_URL="socks5://${WARP_HOST}:${WARP_PORT}"
fi

PROXY_OUTPUT=$(curl -s --max-time 10 --proxy "$PROXY_URL" "$WARP_HEALTH_URL" 2>/dev/null)
PROXY_WARP=$(echo "$PROXY_OUTPUT" | grep -o "^warp=.*" || echo "warp=off")
PROXY_IP=$(echo "$PROXY_OUTPUT" | grep -o "^ip=.*" | cut -d= -f2 || echo "unknown")

echo "  Proxy URL: $PROXY_URL"
echo "  WARP Status: ${PROXY_WARP}"
echo "  Visible IP: ${PROXY_IP}"

echo ""
echo "=== Test 3: IP check ==="
REAL_IP=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null || echo "unknown")
echo "  Your real IP: ${REAL_IP}"
echo "  WARP proxy IP: ${PROXY_IP}"

echo ""
echo "=========================================="
echo " RESULT"
echo "=========================================="
PASS=true

if echo "$PROXY_WARP" | grep -qE "warp=(plus|on)"; then
    echo " [PASS] WARP is active!"
else
    echo " [FAIL] WARP not working (warp=off)"
    PASS=false
fi

if [ "$PROXY_IP" != "$REAL_IP" ] && [ "$PROXY_IP" != "unknown" ]; then
    echo " [PASS] IP changed (${PROXY_IP})"
else
    echo " [FAIL] IP not changed or unknown"
    PASS=false
fi

if $PASS; then
    echo ""
    echo " Next steps for 9Router:"
    echo "   1. Open 9Router dashboard → Proxy Pools → Add Pool"
    echo "   2. Type: SOCKS5"
    echo "   3. URL: ${PROXY_URL}"
    echo "   4. Bind to OpenCode Free provider"
    exit 0
else
    echo ""
    echo " Troubleshooting:"
    echo "   - Is warp container running? (docker ps | grep warp)"
    echo "   - Check logs: docker logs warp-proxy"
    echo "   - Restart: docker compose restart"
    exit 1
fi
