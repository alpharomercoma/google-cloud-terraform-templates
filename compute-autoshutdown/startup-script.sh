#!/bin/bash
set -e

# =============================================================================
# SSH Inactivity Auto-Shutdown Script
# =============================================================================
# This startup script implements SSH session-based inactivity detection.
# It checks for active SSH sessions every ${check_interval_min} minutes and shuts down
# the instance after ${idle_threshold} consecutive checks (${idle_timeout_minutes} minutes) with no activity.
#
# This is the secondary auto-shutdown mechanism. The primary mechanism is
# Cloud Monitoring alerting on low CPU utilization.
# =============================================================================

# Configuration (injected by Terraform templatefile)
IDLE_THRESHOLD=${idle_threshold}
CHECK_INTERVAL_MIN=${check_interval_min}
BOOT_GRACE_PERIOD=${boot_grace_period}
LOG_FILE="/var/log/autoshutdown.log"
STATE_FILE="/var/run/autoshutdown-idle-count"

# Create the auto-shutdown check script
cat > /usr/local/bin/check-ssh-idle.sh << 'SCRIPT'
#!/bin/bash

IDLE_THRESHOLD=${idle_threshold}
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
# Activity Detection - Multiple Methods for Robustness
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
read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
PREV_IDLE=$idle
PREV_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
sleep 1
read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
CURR_IDLE=$idle
CURR_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
DIFF_IDLE=$((CURR_IDLE - PREV_IDLE))
DIFF_TOTAL=$((CURR_TOTAL - PREV_TOTAL))
if [ "$DIFF_TOTAL" -gt 0 ]; then
    CPU_BUSY=$(( (1000 * (DIFF_TOTAL - DIFF_IDLE) / DIFF_TOTAL + 5) / 10 ))
else
    CPU_BUSY=0
fi

# 5. Check for high memory usage (training jobs use lots of memory)
MEM_USED_PCT=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')

# Log current state
echo "$(date): SSH=$ACTIVE_SSH, SSHD=$IAP_SESSIONS, Screen=$SCREEN_SESSIONS, CPU=$CPU_BUSY%, Mem=$MEM_USED_PCT%, IdleCount=$IDLE_COUNT" >> "$LOG_FILE"

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
elif [ "$CPU_BUSY" -gt 10 ]; then
    IS_ACTIVE=1
    REASON="CPU busy ($CPU_BUSY% > 10%)"
elif [ "$MEM_USED_PCT" -gt 80 ]; then
    IS_ACTIVE=1
    REASON="High memory usage ($MEM_USED_PCT% > 80%)"
fi

if [ "$IS_ACTIVE" -eq 0 ]; then
    IDLE_COUNT=$((IDLE_COUNT + 1))
    echo "$IDLE_COUNT" > "$STATE_FILE"
    echo "$(date): No activity detected. Idle count: $IDLE_COUNT/$IDLE_THRESHOLD" >> "$LOG_FILE"

    if [ "$IDLE_COUNT" -ge "$IDLE_THRESHOLD" ]; then
        echo "$(date): IDLE THRESHOLD REACHED. Initiating shutdown..." >> "$LOG_FILE"
        sync
        /sbin/shutdown -h now "Auto-shutdown: No SSH activity detected"
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
cat > /etc/systemd/system/autoshutdown.service << EOF
[Unit]
Description=Check for SSH inactivity and shutdown if idle

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-ssh-idle.sh
EOF

# Create systemd timer for periodic checks
cat > /etc/systemd/system/autoshutdown.timer << EOF
[Unit]
Description=Run SSH inactivity check every ${check_interval_min} minutes

[Timer]
OnBootSec=${boot_grace_period}min
OnUnitActiveSec=${check_interval_min}min
Unit=autoshutdown.service

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
systemctl daemon-reload
systemctl enable autoshutdown.timer
systemctl start autoshutdown.timer

# Initialize log file
echo "$(date): Auto-shutdown monitoring initialized" > /var/log/autoshutdown.log
echo "$(date): Idle threshold: ${idle_threshold} checks (${idle_timeout_minutes} minutes)" >> /var/log/autoshutdown.log
echo "$(date): Check interval: ${check_interval_min} minutes" >> /var/log/autoshutdown.log
echo "$(date): Boot grace period: ${boot_grace_period} minutes" >> /var/log/autoshutdown.log
