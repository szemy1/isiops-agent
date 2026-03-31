#!/bin/bash
# IsiOps Insight — Linux Agent Installer
#
# Usage:
#   curl -s <url>/install.sh | sudo bash -s -- --url <webhook> --key <api-key> [options]
#
# Options:
#   --url <url>              Webhook ingestion URL (required)
#   --key <key>              API key (required)
#   --interval <seconds>     Collection interval (default: 60)
#   --collect <list>         Comma-separated: cpu,memory,disk,network,processes,logs,uptime (default: all)
#   --log-paths <list>       Comma-separated log file paths/globs (default: /var/log/syslog,/var/log/auth.log)
#   --log-level <level>      Min journal priority: debug,info,warning,error,critical (default: info)
#   --log-max-lines <n>      Max lines per log file (default: 50)
#
# Environment variables (fallback):
#   ISIOPS_URL, ISIOPS_KEY, ISIOPS_INTERVAL, ISIOPS_COLLECT,
#   ISIOPS_LOG_PATHS, ISIOPS_LOG_LEVEL, ISIOPS_LOG_MAX_LINES

set -e

# Defaults
URL="${ISIOPS_URL:-}"
KEY="${ISIOPS_KEY:-}"
INTERVAL="${ISIOPS_INTERVAL:-60}"
COLLECT="${ISIOPS_COLLECT:-cpu,memory,disk,network,processes,logs,uptime}"
LOG_PATHS="${ISIOPS_LOG_PATHS:-/var/log/syslog,/var/log/auth.log}"
LOG_LEVEL="${ISIOPS_LOG_LEVEL:-info}"
LOG_MAX_LINES="${ISIOPS_LOG_MAX_LINES:-50}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --url) URL="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --collect) COLLECT="$2"; shift 2 ;;
    --log-paths) LOG_PATHS="$2"; shift 2 ;;
    --log-level) LOG_LEVEL="$2"; shift 2 ;;
    --log-max-lines) LOG_MAX_LINES="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "Usage: install.sh --url <webhook-url> --key <api-key> [--interval 60] [--collect cpu,memory,...] [--log-paths /var/log/*]"
  exit 1
fi

# Parse --collect into flags
has() { echo ",$COLLECT," | grep -q ",$1,"; }
DO_CPU=$(has cpu && echo 1 || echo 0)
DO_MEM=$(has memory && echo 1 || echo 0)
DO_DISK=$(has disk && echo 1 || echo 0)
DO_NET=$(has network && echo 1 || echo 0)
DO_PROC=$(has processes && echo 1 || echo 0)
DO_LOGS=$(has logs && echo 1 || echo 0)
DO_UPTIME=$(has uptime && echo 1 || echo 0)

# Map log level to journalctl priority
case "$LOG_LEVEL" in
  debug)    JOURNAL_PRI=7 ;;
  info)     JOURNAL_PRI=6 ;;
  warning)  JOURNAL_PRI=4 ;;
  error)    JOURNAL_PRI=3 ;;
  critical) JOURNAL_PRI=2 ;;
  *)        JOURNAL_PRI=6 ;;
esac

echo "=== IsiOps Agent Installer ==="
echo "  URL:       $URL"
echo "  Interval:  ${INTERVAL}s"
echo "  Collect:   $COLLECT"
echo "  Log paths: $LOG_PATHS"
echo "  Log level: $LOG_LEVEL (journal priority $JOURNAL_PRI)"
echo ""

# Create agent directory
mkdir -p /opt/isiops-agent

# Write config file (so collect.sh reads it at runtime)
cat > /opt/isiops-agent/agent.conf << CONF_EOF
# IsiOps Agent Configuration — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
ISIOPS_URL="$URL"
ISIOPS_KEY="$KEY"
ISIOPS_COLLECT="$COLLECT"
ISIOPS_LOG_PATHS="$LOG_PATHS"
ISIOPS_LOG_LEVEL="$LOG_LEVEL"
ISIOPS_LOG_MAX_LINES="$LOG_MAX_LINES"
ISIOPS_JOURNAL_PRI="$JOURNAL_PRI"
CONF_EOF

# Write the collection script — reads config from agent.conf
cat > /opt/isiops-agent/collect.sh << 'COLLECT_EOF'
#!/bin/bash
# Source config
source /opt/isiops-agent/agent.conf

URL="$ISIOPS_URL"
KEY="$ISIOPS_KEY"
HOST=$(hostname)
IP=$(hostname -I 2>/dev/null | awk '{ print $1 }')

has() { echo ",$ISIOPS_COLLECT," | grep -q ",$1,"; }

send() {
  curl -sS "$URL" -H "X-Intake-Key: $KEY" -H "Content-Type: application/json" -d "$1" 2>/dev/null
}

# CPU
if has cpu; then
  CPU_COUNT=$(nproc 2>/dev/null || echo 1)
  CPU_IDLE=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/{print $8}' || echo 0)
  CPU_USED=$(echo "100 - ${CPU_IDLE:-0}" | bc 2>/dev/null || echo 0)
  send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"cpu.usage\",\"value\":$CPU_USED,\"unit\":\"percent\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"cpu_count\":\"$CPU_COUNT\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"
fi

# Memory (percentage)
if has memory; then
  MEM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
  MEM_USED=$(free -m 2>/dev/null | awk '/Mem:/{print $3}')
  MEM_FREE=$(free -m 2>/dev/null | awk '/Mem:/{print $4}')
  if [ -n "$MEM_TOTAL" ] && [ "$MEM_TOTAL" -gt 0 ]; then
    MEM_PCT=$(echo "scale=1; $MEM_USED * 100 / $MEM_TOTAL" | bc 2>/dev/null || echo 0)
  else
    MEM_PCT=0
  fi
  send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"memory.usage\",\"value\":$MEM_PCT,\"unit\":\"percent\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"total_mb\":\"$MEM_TOTAL\",\"used_mb\":\"$MEM_USED\",\"free_mb\":\"$MEM_FREE\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"
fi

# Disk (percentage)
if has disk; then
  DISK_PCT=$(df / 2>/dev/null | tail -1 | awk '{gsub(/%/,""); print $5}')
  DISK_TOTAL=$(df -h / 2>/dev/null | tail -1 | awk '{print $2}')
  DISK_USED=$(df -h / 2>/dev/null | tail -1 | awk '{print $3}')
  send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"disk.usage\",\"value\":${DISK_PCT:-0},\"unit\":\"percent\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"total\":\"$DISK_TOTAL\",\"used\":\"$DISK_USED\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"
fi

# Network
if has network; then
  NET_DATA=$(cat /proc/net/dev 2>/dev/null | tail -n+3 | grep -v lo | head -1)
  NET_IFACE=$(echo "$NET_DATA" | awk -F: '{print $1}' | xargs)
  NET_RX=$(echo "$NET_DATA" | awk '{print $2}')
  NET_TX=$(echo "$NET_DATA" | awk '{print $10}')
  send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"network.io\",\"value\":1,\"unit\":\"bytes\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"interface\":\"$NET_IFACE\",\"rx_bytes\":\"$NET_RX\",\"tx_bytes\":\"$NET_TX\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"
fi

# Uptime
if has uptime; then
  UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
  OS_NAME=$(uname -s)
  OS_VER=$(uname -r)
  send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"system.uptime\",\"value\":$UPTIME_SEC,\"unit\":\"seconds\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"os\":\"$OS_NAME\",\"os_version\":\"$OS_VER\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"
fi

# Logs
if has logs; then
  # journalctl
  if command -v journalctl &>/dev/null; then
    LOGS=$(journalctl --since "120 seconds ago" --no-pager --priority="${ISIOPS_JOURNAL_PRI}" -o json 2>/dev/null | head -"${ISIOPS_LOG_MAX_LINES}" | jq -cs '.' 2>/dev/null || echo '[]')
    if [ "$LOGS" != "[]" ]; then
      send "{\"sourceId\":\"$HOST\",\"category\":\"log\",\"severity\":\"info\",\"payload\":{\"message\":\"journal_batch\",\"source\":\"journalctl\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"entries\":$LOGS}},\"tags\":{\"agent\":\"isiops-agent\"}}"
    fi
  fi

  # File-based logs from configured paths
  IFS=',' read -ra PATHS <<< "$ISIOPS_LOG_PATHS"
  for LOGGLOB in "${PATHS[@]}"; do
    for LOGFILE in $LOGGLOB; do
      [ -f "$LOGFILE" ] || continue
      LINES=$(tail -n "${ISIOPS_LOG_MAX_LINES}" "$LOGFILE" 2>/dev/null | jq -Rcs '[split("\n")[] | select(length>0)]' 2>/dev/null || echo '[]')
      [ "$LINES" = "[]" ] && continue
      send "{\"sourceId\":\"$HOST\",\"category\":\"log\",\"severity\":\"info\",\"payload\":{\"message\":\"file_log_batch\",\"source\":\"$LOGFILE\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"entries\":$LINES}},\"tags\":{\"agent\":\"isiops-agent\"}}"
    done
  done
fi
COLLECT_EOF

chmod +x /opt/isiops-agent/collect.sh

# Create systemd service
cat > /etc/systemd/system/isiops-agent.service << UNIT_EOF
[Unit]
Description=IsiOps Insight Telemetry Agent
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash -c "while true; do /opt/isiops-agent/collect.sh; sleep $INTERVAL; done"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT_EOF

# Enable and (re)start
systemctl daemon-reload
systemctl enable isiops-agent
systemctl restart isiops-agent

echo ""
echo "=== IsiOps Agent installed ==="
echo "  Config:   /opt/isiops-agent/agent.conf"
echo "  Script:   /opt/isiops-agent/collect.sh"
echo "  Service:  isiops-agent.service"
echo "  Interval: ${INTERVAL}s"
echo "  Collect:  $COLLECT"
echo "  Logs:     $LOG_PATHS"
echo "  Status:   $(systemctl is-active isiops-agent)"
