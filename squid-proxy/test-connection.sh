#!/bin/bash
# Simple connection test for Squid proxy using .env configuration
set -u

ENV_FILE="/home/ubuntu/9router-proxypool/squid-proxy/.env"

echo "=========================================="
echo " Squid Proxy Connection Test (env-based)"
echo "=========================================="

if [ ! -f "$ENV_FILE" ]; then
    echo "[FAIL] .env file not found at: $ENV_FILE"
    exit 1
fi

set -a
. "$ENV_FILE"
set +a

echo ""
echo "=== Loaded config from .env ==="
echo "  Username : $SQUID_USERNAME"
echo "  Password : ${SQUID_PASSWORD:0:3}*** (hidden)"
echo "  Host:Port: $SQUID_HOST:$SQUID_PORT"
echo "  Check URL: $HEALTH_CHECK_URL"

echo ""
echo "=== Test 1: Direct connection (no proxy) ==="
DIRECT_IP=$(curl -s --max-time 10 https://httpbin.org/ip 2>/dev/null | grep -oE '"origin": "[^"]+"' | head -1)
echo "  Direct IP: ${DIRECT_IP:-FAILED}"

echo ""
echo "=== Test 2: Via Squid proxy ==="
PROXY_URL="http://${SQUID_USERNAME}:${SQUID_PASSWORD}@${SQUID_HOST}:${SQUID_PORT}"
HTTP_CODE=$(curl -s -o /tmp/proxy-response.json -w "%{http_code}" --max-time 10 --proxy "$PROXY_URL" "$HEALTH_CHECK_URL")
PROXY_IP=$(grep -oE '"origin": "[^"]+"' /tmp/proxy-response.json 2>/dev/null | head -1)
echo "  HTTP Code: $HTTP_CODE"
echo "  Proxy IP : ${PROXY_IP:-FAILED}"

echo ""
echo "=== Test 3: Wrong credentials (expect rejection) ==="
WRONG_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --proxy "http://${SQUID_USERNAME}:wrongpass@${SQUID_HOST}:${SQUID_PORT}" "$HEALTH_CHECK_URL")
echo "  HTTP Code: $WRONG_CODE (407 or 000=dropped, both mean auth rejected)"

echo ""
echo "=========================================="
echo " RESULT"
echo "=========================================="
PASS=true
[ "$HTTP_CODE" = "200" ] || PASS=false
if [ "$WRONG_CODE" != "407" ] && [ "$WRONG_CODE" != "000" ]; then
    PASS=false
fi

if $PASS; then
    echo " [PASS] Squid proxy works correctly with your .env config"
    echo " [PASS] Authentication enforced (wrong creds rejected)"
    echo ""
    echo " Real IP (direct) : ${DIRECT_IP:-?}"
    echo " Proxy IP         : ${PROXY_IP:-?}"
    echo ""
    echo " Next steps:"
    echo "   1. In 9Router dashboard → Proxy Pools → Add Pool"
    echo "   2. URL: http://${SQUID_USERNAME}:***@${SQUID_HOST}:${SQUID_PORT}"
    echo "   3. Type: Standard HTTP"
    echo "   4. Bind to OpenCode Free provider"
    exit 0
else
    echo " [FAIL] Something is wrong. Check:"
    echo "   - Is the Squid container running? (docker ps | grep squid)"
    echo "   - Are SQUID_USERNAME/PASSWORD in .env correct?"
    echo "   - Is port ${SQUID_PORT} free? (ss -tlnp | grep ${SQUID_PORT})"
    exit 1
fi
