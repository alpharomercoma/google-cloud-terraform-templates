#!/bin/bash
set -e

# =============================================================================
# Multi-Signal Inactivity Auto-Shutdown Script
# =============================================================================
# This startup script implements inactivity detection using multiple independent
# signals and a quorum decision model to reduce false positives.
# =============================================================================

# Configuration (injected by Terraform templatefile)
IDLE_THRESHOLD=${idle_threshold}
CHECK_INTERVAL_MIN=${check_interval_min}
BOOT_GRACE_PERIOD=${boot_grace_period}
CPU_IDLE_THRESHOLD=5
NET_KBPS_THRESHOLD=20
DISK_IOPS_THRESHOLD=2
DISK_KBPS_THRESHOLD=10
WORKLOAD_IDLE_SIGNALS_REQUIRED=2
LOG_FILE="/var/log/autoshutdown.log"
STATE_FILE="/var/run/autoshutdown-idle-count"

# Create the auto-shutdown check script
cat > /usr/local/bin/check-ssh-idle.sh << 'SCRIPT'
#!/bin/bash

IDLE_THRESHOLD=${idle_threshold}
CPU_IDLE_THRESHOLD=5
NET_KBPS_THRESHOLD=20
DISK_IOPS_THRESHOLD=2
DISK_KBPS_THRESHOLD=10
WORKLOAD_IDLE_SIGNALS_REQUIRED=2
LOG_FILE="/var/log/autoshutdown.log"
STATE_FILE="/var/run/autoshutdown-idle-count"
LOCK_FILE="/var/run/autoshutdown.lock"

# Use file locking to prevent race conditions
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "$(date): Another check is running, skipping." >> "$LOG_FILE"; exit 0; }

# Initialize state file if not exists
if [ ! -f "$STATE_FILE" ]; then
    echo "0" > "$STATE_FILE"
fi

# Get current idle count
IDLE_COUNT=$(cat "$STATE_FILE" 2>/dev/null || echo "0")

# =========================================================================
# Multi-Signal Activity Detection
# =========================================================================

# 1. Check for active SSH sessions via who (pts terminals)
ACTIVE_SSH=$(who 2>/dev/null | grep -c "pts/" || echo "0")

# 2. Check for active gcloud SSH / IAP tunnel sessions
IAP_SESSIONS=$(pgrep -c "sshd" 2>/dev/null || echo "0")
# Subtract 1 for the master sshd process if running
if [ "$IAP_SESSIONS" -gt 0 ]; then
    IAP_SESSIONS=$((IAP_SESSIONS - 1))
fi

# 3. Check for screen/tmux sessions (user might have detached)
SCREEN_SESSIONS=$(pgrep -c "screen\|tmux" 2>/dev/null || echo "0")

# 4. Check CPU usage using /proc/stat
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
PREV_IDLE=$idle
PREV_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
sleep 1
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
CURR_IDLE=$idle
CURR_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
DIFF_IDLE=$((CURR_IDLE - PREV_IDLE))
DIFF_TOTAL=$((CURR_TOTAL - PREV_TOTAL))
if [ "$DIFF_TOTAL" -gt 0 ]; then
    CPU_BUSY=$(( (1000 * (DIFF_TOTAL - DIFF_IDLE) / DIFF_TOTAL + 5) / 10 ))
else
    CPU_BUSY=0
fi

# 5. Check network throughput (combined inbound + outbound)
NET_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
if [ -z "$NET_IFACE" ]; then
    NET_IFACE=$(ls /sys/class/net 2>/dev/null | grep -E -v '^(lo|docker|br-|veth)' | head -1)
fi

NET_KBPS=0
if [ -n "$NET_IFACE" ] && [ -r "/sys/class/net/$NET_IFACE/statistics/rx_bytes" ] && [ -r "/sys/class/net/$NET_IFACE/statistics/tx_bytes" ]; then
    RX1=$(cat "/sys/class/net/$NET_IFACE/statistics/rx_bytes")
    TX1=$(cat "/sys/class/net/$NET_IFACE/statistics/tx_bytes")
    sleep 1
    RX2=$(cat "/sys/class/net/$NET_IFACE/statistics/rx_bytes")
    TX2=$(cat "/sys/class/net/$NET_IFACE/statistics/tx_bytes")
    TOTAL_BYTES=$(( (RX2 - RX1) + (TX2 - TX1) ))
    NET_KBPS=$(( TOTAL_BYTES / 1024 ))
fi

# 6. Check disk I/O activity (combined read/write IOPS + throughput)
read -r DISK_IO1 DISK_SECTORS1 <<< "$(awk '$3 !~ /^(loop|ram|fd|sr|dm-|md)/ {io += $4 + $8; sectors += $6 + $10} END {print io + 0, sectors + 0}' /proc/diskstats)"
sleep 1
read -r DISK_IO2 DISK_SECTORS2 <<< "$(awk '$3 !~ /^(loop|ram|fd|sr|dm-|md)/ {io += $4 + $8; sectors += $6 + $10} END {print io + 0, sectors + 0}' /proc/diskstats)"
DISK_IOPS=$((DISK_IO2 - DISK_IO1))
DISK_KBPS=$(( ((DISK_SECTORS2 - DISK_SECTORS1) * 512) / 1024 ))

# Determine workload idle quorum (2 of 3 signals: CPU, network, disk)
WORKLOAD_IDLE_SIGNALS=0
WORKLOAD_REASON=""

if [ "$CPU_BUSY" -lt "$CPU_IDLE_THRESHOLD" ]; then
    WORKLOAD_IDLE_SIGNALS=$((WORKLOAD_IDLE_SIGNALS + 1))
    if [ -n "$WORKLOAD_REASON" ]; then
        WORKLOAD_REASON="$WORKLOAD_REASON; "
    fi
    WORKLOAD_REASON="$WORKLOAD_REASON""cpu=$CPU_BUSY%"
fi

if [ "$NET_KBPS" -lt "$NET_KBPS_THRESHOLD" ]; then
    WORKLOAD_IDLE_SIGNALS=$((WORKLOAD_IDLE_SIGNALS + 1))
    if [ -n "$WORKLOAD_REASON" ]; then
        WORKLOAD_REASON="$WORKLOAD_REASON; "
    fi
    WORKLOAD_REASON="$WORKLOAD_REASON""net=$NET_KBPS KB/s"
fi

if [ "$DISK_IOPS" -lt "$DISK_IOPS_THRESHOLD" ] && [ "$DISK_KBPS" -lt "$DISK_KBPS_THRESHOLD" ]; then
    WORKLOAD_IDLE_SIGNALS=$((WORKLOAD_IDLE_SIGNALS + 1))
    if [ -n "$WORKLOAD_REASON" ]; then
        WORKLOAD_REASON="$WORKLOAD_REASON; "
    fi
    WORKLOAD_REASON="$WORKLOAD_REASON""disk=$DISK_IOPS IOPS/$DISK_KBPS KB/s"
fi

# Log current state
echo "$(date): SSH=$ACTIVE_SSH, SSHD=$IAP_SESSIONS, Screen=$SCREEN_SESSIONS, CPU=$CPU_BUSY%, NET=$NET_KBPS KB/s, DISK=$DISK_IOPS IOPS/$DISK_KBPS KB/s, WorkloadIdleSignals=$WORKLOAD_IDLE_SIGNALS/3, IdleCount=$IDLE_COUNT" >> "$LOG_FILE"

# Determine if system is active
IS_ACTIVE=0
REASON=""

if [ "$ACTIVE_SSH" -gt 0 ]; then
    IS_ACTIVE=1
    REASON="Active SSH sessions ($ACTIVE_SSH)"
elif [ "$IAP_SESSIONS" -gt 0 ]; then
    IS_ACTIVE=1
    REASON="Active SSHD child processes ($IAP_SESSIONS)"
elif [ "$SCREEN_SESSIONS" -gt 0 ]; then
    IS_ACTIVE=1
    REASON="Screen/tmux sessions running"
elif [ "$WORKLOAD_IDLE_SIGNALS" -lt "$WORKLOAD_IDLE_SIGNALS_REQUIRED" ]; then
    IS_ACTIVE=1
    REASON="Idle quorum not met ($WORKLOAD_IDLE_SIGNALS/3 workload signals idle)"
fi

if [ "$IS_ACTIVE" -eq 0 ]; then
    IDLE_COUNT=$((IDLE_COUNT + 1))
    echo "$IDLE_COUNT" > "$STATE_FILE"
    echo "$(date): Idle quorum met (ssh/session idle, workload_idle_signals=$WORKLOAD_IDLE_SIGNALS). Idle count: $IDLE_COUNT/$IDLE_THRESHOLD" >> "$LOG_FILE"

    if [ "$IDLE_COUNT" -ge "$IDLE_THRESHOLD" ]; then
        echo "$(date): IDLE THRESHOLD REACHED. Initiating shutdown..." >> "$LOG_FILE"
        sync
        /sbin/shutdown -h now "Auto-shutdown: SSH/session idle and workload idle quorum met ($WORKLOAD_REASON)"
    fi
else
    echo "0" > "$STATE_FILE"
    echo "$(date): Activity detected ($REASON). Idle count reset." >> "$LOG_FILE"
fi

# Release lock
flock -u 200
SCRIPT

chmod +x /usr/local/bin/check-ssh-idle.sh

# Create systemd service
cat > /etc/systemd/system/autoshutdown.service << EOF2
[Unit]
Description=Check for multi-signal inactivity and shutdown if idle

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-ssh-idle.sh
EOF2

# Create systemd timer for periodic checks
cat > /etc/systemd/system/autoshutdown.timer << EOF2
[Unit]
Description=Run inactivity check every ${check_interval_min} minutes

[Timer]
OnBootSec=${boot_grace_period}min
OnUnitActiveSec=${check_interval_min}min
Unit=autoshutdown.service

[Install]
WantedBy=timers.target
EOF2

# Enable and start the timer
systemctl daemon-reload
systemctl enable autoshutdown.timer
systemctl start autoshutdown.timer

# Initialize log file
echo "$(date): Auto-shutdown monitoring initialized" > /var/log/autoshutdown.log
echo "$(date): Idle threshold: ${idle_threshold} checks (${idle_timeout_minutes} minutes)" >> /var/log/autoshutdown.log
echo "$(date): Check interval: ${check_interval_min} minutes" >> /var/log/autoshutdown.log
echo "$(date): Boot grace period: ${boot_grace_period} minutes" >> /var/log/autoshutdown.log
echo "$(date): Workload thresholds: CPU<5%, NET<20KB/s, DISK<2IOPS and <10KB/s" >> /var/log/autoshutdown.log
echo "$(date): Decision rule: SSH/session idle AND at least 2 workload idle signals" >> /var/log/autoshutdown.log
