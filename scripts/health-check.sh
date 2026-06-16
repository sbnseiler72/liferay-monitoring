#!/bin/bash
# =============================================================================
# Liferay Monitor — Daily Health Check
# Usage: bash scripts/health-check.sh
# Add to crontab for automated daily report:
#   0 8 * * * bash /path/to/liferay-monitor/scripts/health-check.sh >> /var/log/liferay-health.log 2>&1
# =============================================================================

# Load .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/.env" 2>/dev/null || true

LIFERAY_CONTAINER=${LIFERAY_CONTAINER:-liferay}
DB_CONTAINER=${DB_CONTAINER:-db}
NGINX_CONTAINER=${NGINX_CONTAINER:-web-server}
POSTGRES_USER=${POSTGRES_USER:-liferay}
POSTGRES_DB=${POSTGRES_DB:-portal737}

LINE="─────────────────────────────────────────────────────"
PASS="  ✓"
WARN="  ⚠"
FAIL="  ✗"

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║     Liferay Portal — Health Check                  ║"
echo "║     $(date '+%Y-%m-%d %H:%M:%S %Z')                   ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# --- Container Status ---
echo "[ Container Status ]"
echo "$LINE"
for container in "$LIFERAY_CONTAINER" "$DB_CONTAINER" "$NGINX_CONTAINER" elasticsearch; do
    STATUS=$(docker inspect "$container" --format='{{.State.Status}}' 2>/dev/null || echo "not found")
    RESTARTS=$(docker inspect "$container" --format='{{.RestartCount}}' 2>/dev/null || echo "?")
    OOM=$(docker inspect "$container" --format='{{.State.OOMKilled}}' 2>/dev/null || echo "?")
    if [ "$STATUS" = "running" ]; then
        echo "$PASS $container: running | restarts=$RESTARTS | oom_killed=$OOM"
    else
        echo "$FAIL $container: $STATUS | restarts=$RESTARTS | oom_killed=$OOM"
    fi
done
echo ""

# --- Memory Usage ---
echo "[ Container Memory ]"
echo "$LINE"
docker stats --no-stream \
    "$LIFERAY_CONTAINER" "$DB_CONTAINER" "$NGINX_CONTAINER" elasticsearch \
    --format "  {{.Name}}: {{.MemUsage}} ({{.MemPerc}})" 2>/dev/null || echo "  Unable to read stats"
echo ""

# --- GC Log Analysis ---
echo "[ GC Health (today) ]"
echo "$LINE"

# Find liferay logs directory
LF_LOG_DIR=""
for path in \
    "$ROOT_DIR/../liferay/logs" \
    "/opt/liferay/logs" \
    "$HOME/liferay-elasticsearch-composer/liferay/logs"; do
    if [ -d "$path" ]; then
        LF_LOG_DIR="$path"
        break
    fi
done

if [ -n "$LF_LOG_DIR" ]; then
    TOSPACE=$(grep -c "to-space exhausted" "$LF_LOG_DIR"/gc.log.*.current 2>/dev/null || echo 0)
    HUMONGOUS=$(grep -c "Humongous Allocation" "$LF_LOG_DIR"/gc.log.*.current 2>/dev/null || echo 0)
    FULLGC=$(grep -c "G1 Old Generation" "$LF_LOG_DIR"/gc.log.*.current 2>/dev/null || echo 0)

    [ "$TOSPACE" = "0" ] && echo "$PASS to-space exhausted events: 0" || echo "$FAIL to-space exhausted events: $TOSPACE (CRITICAL — crash precursor)"
    [ "$HUMONGOUS" -lt 20 ] && echo "$PASS humongous allocations: $HUMONGOUS" || echo "$WARN humongous allocations: $HUMONGOUS (elevated)"
    [ "$FULLGC" = "0" ] && echo "$PASS full GC (G1 Old) events: 0" || echo "$WARN full GC events: $FULLGC"

    TODAY_LOG="$LF_LOG_DIR/liferay.$(date '+%Y-%m-%d').log"
    if [ -f "$TODAY_LOG" ]; then
        BROKEN_PIPE=$(grep -c "Broken pipe" "$TODAY_LOG" 2>/dev/null || echo 0)
        PDF_FAIL=$(grep -c "Unable to process" "$TODAY_LOG" 2>/dev/null || echo 0)
        ERRORS=$(grep -c "ERROR" "$TODAY_LOG" 2>/dev/null || echo 0)
        [ "$BROKEN_PIPE" -lt 10 ] && echo "$PASS broken pipe errors today: $BROKEN_PIPE" || echo "$WARN broken pipe errors today: $BROKEN_PIPE"
        [ "$PDF_FAIL" = "0" ] && echo "$PASS PDF processor failures today: 0" || echo "$WARN PDF processor failures today: $PDF_FAIL"
        [ "$ERRORS" -lt 50 ] && echo "$PASS Liferay ERROR lines today: $ERRORS" || echo "$WARN Liferay ERROR lines today: $ERRORS"
    fi
else
    echo "  Liferay log directory not found — set LF_LOG_DIR in script"
fi
echo ""

# --- Nginx Cache Stats ---
echo "[ Nginx Cache Stats ]"
echo "$LINE"

NGINX_LOG_DIR=""
for path in \
    "$ROOT_DIR/../nginx/logs" \
    "$HOME/liferay-elasticsearch-composer/nginx/logs"; do
    if [ -d "$path" ]; then
        NGINX_LOG_DIR="$path"
        break
    fi
done

if [ -n "$NGINX_LOG_DIR" ] && [ -f "$NGINX_LOG_DIR/js_cache.log" ]; then
    awk '{
        match($0, /cs=[A-Z_]+/);
        cs = substr($0, RSTART+3, RLENGTH-3);
        if (cs != "") { total++; if (cs == "HIT") hits++ }
    }
    END {
        if (total == 0) { print "  No cache log entries"; exit }
        rate = hits/total*100;
        printf "  Hit rate: %.1f%% (%d/%d requests)\n", rate, hits, total;
        if (rate < 80) print "  ⚠ Hit rate below 80% — check cache config"
        else if (rate > 95) print "  ✓ Cache performance excellent"
        else print "  ✓ Cache performance good"
    }' "$NGINX_LOG_DIR/js_cache.log"
else
    echo "  js_cache.log not found"
fi
echo ""

# --- PostgreSQL ---
echo "[ PostgreSQL ]"
echo "$LINE"
PG_CONN=$(docker exec "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE state='active';" 2>/dev/null | tr -d ' ' || echo "?")
PG_SIZE=$(docker exec "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t \
    -c "SELECT pg_size_pretty(pg_database_size(current_database()));" 2>/dev/null | tr -d ' ' || echo "?")
echo "  Active connections: $PG_CONN"
echo "  Database size: $PG_SIZE"
echo ""

# --- Disk ---
echo "[ Disk Usage ]"
echo "$LINE"
df -h / | awk 'NR==2{print "  Root filesystem: "$3" used of "$2" ("$5")"}'
echo ""

# --- Monitor Stack Status ---
echo "[ Monitor Stack ]"
echo "$LINE"
for container in lf_monitor_prometheus lf_monitor_grafana lf_monitor_cadvisor \
                 lf_monitor_jmx lf_monitor_postgres lf_monitor_nginx; do
    STATUS=$(docker inspect "$container" --format='{{.State.Status}}' 2>/dev/null || echo "not running")
    [ "$STATUS" = "running" ] && echo "$PASS $container" || echo "$WARN $container: $STATUS"
done

echo ""
echo "$LINE"
echo "  Report complete — $(date '+%H:%M:%S')"
echo ""
