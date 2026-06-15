#!/bin/bash
# Test Cloudflare WARP proxy connection + IP rotation
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
WARP_PORT="${WARP_PORT:-10800}"
WARP_HEALTH_URL="${WARP_HEALTH_URL:-https://cloudflare.com/cdn-cgi/trace}"
WARP_PROXY_USER="${WARP_PROXY_USER:-}"
WARP_PROXY_PASS="${WARP_PROXY_PASS:-}"
WARP_INSTANCES="${WARP_INSTANCES:-1}"

echo "=========================================="
echo " Cloudflare WARP Test + IP Rotation"
echo "=========================================="
echo ""

PROXY_URL="socks5://${WARP_PROXY_USER}:${WARP_PROXY_PASS}@${WARP_HOST}:${WARP_PORT}"

echo "=== Test 1: WARP status ==="
PROXY_OUTPUT=$(curl -s --max-time 10 --proxy "$PROXY_URL" "$WARP_HEALTH_URL" 2>/dev/null)
PROXY_WARP=$(echo "$PROXY_OUTPUT" | grep -o "^warp=.*" || echo "warp=off")
PROXY_IP=$(echo "$PROXY_OUTPUT" | grep -o "^ip=.*" | cut -d= -f2 || echo "unknown")
echo "  WARP Status: ${PROXY_WARP}"
echo "  Visible IP: ${PROXY_IP}"
echo ""

echo "=== Test 2: Auth rejection (no creds) ==="
AUTH_TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --proxy "socks5://${WARP_HOST}:${WARP_PORT}" "$WARP_HEALTH_URL" 2>/dev/null)
if [ "$AUTH_TEST" = "000" ]; then
    echo "  [PASS] Unauthenticated requests rejected"
else
    echo "  [FAIL] Proxy may be open (no auth) - got HTTP $AUTH_TEST"
fi
echo ""

echo "=== Test 3: IP Rotation (${WARP_INSTANCES} instances) ==="
echo "  Sending 10 requests, checking IP diversity..."
echo ""
UNIQUE_IPS=$(mktemp)
for i in $(seq 1 10); do
    IP=$(curl -s --max-time 10 --proxy "$PROXY_URL" https://ifconfig.me 2>/dev/null)
    if [ -n "$IP" ]; then
        echo "  Request $i: $IP"
        echo "$IP" >> "$UNIQUE_IPS"
    else
        echo "  Request $i: FAILED"
    fi
done

IP_COUNT=$(sort -u "$UNIQUE_IPS" | grep -c . || echo "0")
rm -f "$UNIQUE_IPS"
echo ""
echo "  Unique IPs seen: $IP_COUNT (out of ${WARP_INSTANCES} instances)"
echo ""

echo "=== Test 4: Real IP comparison ==="
REAL_IP=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null || echo "unknown")
echo "  Your real IP: ${REAL_IP}"
echo "  WARP exit IP: ${PROXY_IP}"
echo ""

echo "=========================================="
echo " RESULT"
echo "=========================================="
PASS=true

if echo "$PROXY_WARP" | grep -qE "warp=(plus|on)"; then
    echo " [PASS] WARP is active"
else
    echo " [FAIL] WARP not working (warp=off)"
    PASS=false
fi

if [ "$IP_COUNT" -ge 2 ] 2>/dev/null; then
    echo " [PASS] IP rotation working ($IP_COUNT unique IPs)"
elif [ "$WARP_INSTANCES" -gt 1 ]; then
    echo " [WARN] Only $IP_COUNT unique IP - rotation may need warm-up"
else
    echo " [INFO] Single instance (no rotation expected)"
fi

if [ "$PROXY_IP" != "$REAL_IP" ] && [ "$PROXY_IP" != "unknown" ]; then
    echo " [PASS] IP changed (${PROXY_IP})"
else
    echo " [FAIL] IP not changed"
    PASS=false
fi

if $PASS; then
    echo ""
    echo " 9Router Proxy URL (unchanged):"
    echo "   ${PROXY_URL}"
    exit 0
else
    echo ""
    echo " Troubleshooting:"
    echo "   - docker compose ps"
    echo "   - docker logs warp-proxy --tail 30"
    echo "   - docker compose restart"
    exit 1
fi
