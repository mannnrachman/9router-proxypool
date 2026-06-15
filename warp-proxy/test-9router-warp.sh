#!/bin/bash
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

ROUTER_HOST="${ROUTER_HOST:-10.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-20128}"
WARP_HOST="${WARP_HOST:-127.0.0.1}"
WARP_PORT="${WARP_PORT:-10800}"
WARP_PROXY_USER="${WARP_PROXY_USER:-}"
WARP_PROXY_PASS="${WARP_PROXY_PASS:-}"
PROXY_URL="socks5://${WARP_PROXY_USER}:${WARP_PROXY_PASS}@${WARP_HOST}:${WARP_PORT}"

echo "=========================================="
echo " 9Router + WARP Integration Test"
echo "=========================================="
echo ""

echo "=== Checking 9Router ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${ROUTER_HOST}:${ROUTER_PORT}/dashboard" 2>/dev/null)
if test "$HTTP_CODE" = "200" -o "$HTTP_CODE" = "302"; then
    echo " [PASS] 9Router is running (HTTP $HTTP_CODE)"
else
    echo " [FAIL] 9Router not accessible at http://${ROUTER_HOST}:${ROUTER_PORT}/dashboard (HTTP $HTTP_CODE)"
    echo "   Start 9Router first"
    exit 1
fi

echo ""
echo "=== Checking WARP Proxy ==="
WARP_IP=$(curl -s --max-time 10 --proxy "$PROXY_URL" https://ifconfig.me 2>/dev/null)
if test -n "$WARP_IP"; then
    echo " [PASS] WARP proxy working (IP: $WARP_IP)"
else
    echo " [FAIL] WARP proxy not responding"
    exit 1
fi

echo ""
echo "Setup complete! Add proxy in 9Router dashboard:"
echo "  Proxy Pools → Add → SOCKS5 → ${PROXY_URL}"
