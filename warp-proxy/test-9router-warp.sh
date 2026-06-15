#!/bin/bash
echo "=========================================="
echo " 9Router + WARP Integration Test"
echo "=========================================="
echo ""

echo "=== Checking 9Router ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:20128/dashboard 2>/dev/null)
if test "$HTTP_CODE" = "200" -o "$HTTP_CODE" = "302"; then
    echo " [PASS] 9Router is running (HTTP $HTTP_CODE)"
else
    echo " [FAIL] 9Router not accessible (HTTP $HTTP_CODE)"
    echo "   Start 9Router first"
    exit 1
fi

echo ""
echo "=== Checking WARP Proxy ==="
WARP_IP=$(curl -s --max-time 10 --proxy socks5://127.0.0.1:10800 https://ifconfig.me 2>/dev/null)
if test -n "$WARP_IP"; then
    echo " [PASS] WARP proxy working (IP: $WARP_IP)"
else
    echo " [FAIL] WARP proxy not responding"
    exit 1
fi

echo ""
echo "Setup complete! Add proxy in 9Router dashboard:"
echo "  Proxy Pools → Add → SOCKS5 → socks5://127.0.0.1:10800"
