#!/bin/bash
# IsiOps Insight — Linux Agent Installer
# Usage: curl -s <raw-url>/linux/install.sh | sudo bash -s -- --url <webhook-url> --key <api-key>
#
# Or set environment variables:
#   ISIOPS_URL=https://your-opcenter/webhook/telemetry
#   ISIOPS_KEY=opck_...
#   ISIOPS_INTERVAL=60

set -e

# Parse arguments
URL="${ISIOPS_URL:-}"
KEY="${ISIOPS_KEY:-}"
INTERVAL="${ISIOPS_INTERVAL:-60}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --url) URL="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "Usage: install.sh --url <webhook-url> --key <api-key> [--interval 60]"
  echo "  Or set ISIOPS_URL and ISIOPS_KEY environment variables"
  exit 1
fi

echo "=== IsiOps Agent Installer ==="
echo "  URL:      $URL"
echo "  Interval: ${INTERVAL}s"
echo ""

# Create agent directory
mkdir -p /opt/isiops-agent

# Write the collection script
cat > /opt/isiops-agent/collect.sh << 'COLLECT_EOF'
#!/bin/bash
URL="__URL__"
KEY="__KEY__"
HOST=$(hostname)
IP=$(hostname -I 2>/dev/null | awk '{ print $1 }')

send() {
  curl -sS "$URL" -H "X-Intake-Key: $KEY" -H "Content-Type: application/json" -d "$1" 2>/dev/null
}

# CPU
CPU_COUNT=$(nproc 2>/dev/null || echo 1)
CPU_IDLE=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/{print $8}' || echo 0)
CPU_USED=$(echo "100 - ${CPU_IDLE:-0}" | bc 2>/dev/null || echo 0)
send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"cpu.usage\",\"value\":$CPU_USED,\"unit\":\"percent\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"cpu_count\":\"$CPU_COUNT\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"

# Memory (percentage)
MEM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
MEM_USED=$(free -m 2>/dev/null | awk '/Mem:/{print $3}')
MEM_FREE=$(free -m 2>/dev/null | awk '/Mem:/{print $4}')
if [ -n "$MEM_TOTAL" ] && [ "$MEM_TOTAL" -gt 0 ]; then
  MEM_PCT=$(echo "scale=1; $MEM_USED * 100 / $MEM_TOTAL" | bc 2>/dev/null || echo 0)
else
  MEM_PCT=0
fi
send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"memory.usage\",\"value\":$MEM_PCT,\"unit\":\"percent\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"total_mb\":\"$MEM_TOTAL\",\"used_mb\":\"$MEM_USED\",\"free_mb\":\"$MEM_FREE\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"

# Disk (percentage)
DISK_PCT=$(df / 2>/dev/null | tail -1 | awk '{gsub(/%/,""); print $5}')
DISK_TOTAL=$(df -h / 2>/dev/null | tail -1 | awk '{print $2}')
DISK_USED=$(df -h / 2>/dev/null | tail -1 | awk '{print $3}')
send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"disk.usage\",\"value\":${DISK_PCT:-0},\"unit\":\"percent\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"total\":\"$DISK_TOTAL\",\"used\":\"$DISK_USED\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"

# Network
NET_DATA=$(cat /proc/net/dev 2>/dev/null | tail -n+3 | grep -v lo | head -1)
NET_IFACE=$(echo "$NET_DATA" | awk -F: '{print $1}' | xargs)
NET_RX=$(echo "$NET_DATA" | awk '{print $2}')
NET_TX=$(echo "$NET_DATA" | awk '{print $10}')
send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"network.io\",\"value\":1,\"unit\":\"bytes\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"interface\":\"$NET_IFACE\",\"rx_bytes\":\"$NET_RX\",\"tx_bytes\":\"$NET_TX\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"

# Uptime
UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
OS_NAME=$(uname -s)
OS_VER=$(uname -r)
send "{\"sourceId\":\"$HOST\",\"category\":\"metric\",\"severity\":\"info\",\"payload\":{\"metric\":\"system.uptime\",\"value\":$UPTIME_SEC,\"unit\":\"seconds\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"os\":\"$OS_NAME\",\"os_version\":\"$OS_VER\"}},\"tags\":{\"agent\":\"isiops-agent\"}}"

# Logs — journalctl
if command -v journalctl &>/dev/null; then
  LOGS=$(journalctl --since "120 seconds ago" --no-pager -o json 2>/dev/null | head -50 | jq -cs '.' 2>/dev/null || echo '[]')
  if [ "$LOGS" != "[]" ]; then
    send "{\"sourceId\":\"$HOST\",\"category\":\"log\",\"severity\":\"info\",\"payload\":{\"message\":\"journal_batch\",\"source\":\"journalctl\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"entries\":$LOGS}},\"tags\":{\"agent\":\"isiops-agent\"}}"
  fi
fi

# Logs — syslog / auth.log
for LOGFILE in /var/log/syslog /var/log/auth.log /var/log/messages; do
  [ -f "$LOGFILE" ] || continue
  LINES=$(tail -n 50 "$LOGFILE" 2>/dev/null | jq -Rcs '[split("\n")[] | select(length>0)]' 2>/dev/null || echo '[]')
  [ "$LINES" = "[]" ] && continue
  send "{\"sourceId\":\"$HOST\",\"category\":\"log\",\"severity\":\"info\",\"payload\":{\"message\":\"file_log_batch\",\"source\":\"$LOGFILE\",\"metadata\":{\"hostname\":\"$HOST\",\"ip\":\"$IP\",\"entries\":$LINES}},\"tags\":{\"agent\":\"isiops-agent\"}}"
done
COLLECT_EOF

# Replace placeholders with actual values
sed -i "s|__URL__|$URL|g" /opt/isiops-agent/collect.sh
sed -i "s|__KEY__|$KEY|g" /opt/isiops-agent/collect.sh
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

# Enable and start
systemctl daemon-reload
systemctl enable --now isiops-agent

echo ""
echo "=== IsiOps Agent installed ==="
echo "  Script:   /opt/isiops-agent/collect.sh"
echo "  Service:  isiops-agent.service"
echo "  Interval: ${INTERVAL}s"
echo "  Status:   $(systemctl is-active isiops-agent)"
