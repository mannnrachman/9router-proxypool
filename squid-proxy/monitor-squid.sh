#!/bin/bash
# Squid Proxy Health Monitor & Auto-Restart for 9Router
# Maintained at: /home/ubuntu/9router-proxypool/squid-proxy/
# Cron: */2 * * * * /home/ubuntu/9router-proxypool/squid-proxy/monitor-squid.sh >> /var/log/squid-monitor.log 2>&1

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

# Defaults if env not set
SQUID_USERNAME="${SQUID_USERNAME:-opencode}"
SQUID_PASSWORD="${SQUID_PASSWORD:-CHANGE_ME}"
SQUID_HOST="${SQUID_HOST:-127.0.0.1}"
SQUID_PORT="${SQUID_PORT:-3128}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-https://httpbin.org/ip}"

LOG="/var/log/squid-monitor.log"
CONTAINER="squid-proxy"
COMPOSE_DIR="$SCRIPT_DIR"
HEALTH_URL="http://${SQUID_USERNAME}:${SQUID_PASSWORD}@${SQUID_HOST}:${SQUID_PORT}"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] $1"; }

# 1. Check container running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    log "ALERT: Container $CONTAINER not running! Attempting restart..."
    cd "$COMPOSE_DIR" && docker compose up -d 2>&1 | tail -3
    sleep 5
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        log "RECOVERED: Container successfully restarted"
    else
        log "CRITICAL: Container failed to restart!"
        exit 2
    fi
fi

# 2. Check health status
HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "none")
if [ "$HEALTH" = "unhealthy" ]; then
    log "ALERT: Container health=unhealthy. Restarting..."
    docker restart "$CONTAINER" 2>&1 | tail -1
    sleep 8
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "none")
    log "POST-RESTART health=$HEALTH"
fi

# 3. Check proxy actually accepts requests (HTTP 200 from health URL)
PROXY_TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
    --proxy "$HEALTH_URL" "$HEALTH_CHECK_URL" 2>/dev/null || echo "000")

if [ "$PROXY_TEST" != "200" ]; then
    log "ALERT: Proxy unresponsive (HTTP $PROXY_TEST). Restarting container..."
    docker restart "$CONTAINER" 2>&1 | tail -1
    sleep 8
    PROXY_TEST2=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
        --proxy "$HEALTH_URL" "$HEALTH_CHECK_URL" 2>/dev/null || echo "000")
    if [ "$PROXY_TEST2" = "200" ]; then
        log "RECOVERED: Proxy back to normal (HTTP 200)"
    else
        log "CRITICAL: Proxy still failing (HTTP $PROXY_TEST2)"
        exit 3
    fi
fi

# 4. Check 9Router binding intact
POOL_ID=$(sqlite3 /home/ubuntu/.9router/db/data.sqlite \
    "SELECT json_extract(data,'\$.providerStrategies.opencode.proxyPoolId') FROM settings WHERE id=1;" 2>/dev/null)
if [ -z "$POOL_ID" ] || [ "$POOL_ID" = "null" ]; then
    log "WARNING: 9Router binding for opencode is missing!"
fi

# 5. Check 9Router service
if ! systemctl is-active --quiet 9router.service; then
    log "ALERT: 9router.service down! Restarting..."
    sudo systemctl restart 9router.service
    sleep 5
fi

# All good, minimal log
log "OK: container=$HEALTH proxy=HTTP$PROXY_TEST 9router=active"
exit 0
