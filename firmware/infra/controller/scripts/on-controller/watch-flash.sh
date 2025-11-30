#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Watch flash log and stop when flash completes or errors
# This script runs on the remote controller

LOG_FILE="/tmp/usb-flash.log"
SESSION_NAME="usb-flash"

# Wait for log file to exist (flash might have just started)
# Add timeout to prevent infinite waiting
wait_count=0
max_wait=30
while [ ! -f "$LOG_FILE" ] && [ $wait_count -lt $max_wait ]; do
    sleep 1
    wait_count=$((wait_count + 1))
done

if [ ! -f "$LOG_FILE" ]; then
    echo "Warning: Log file not found after waiting. Flash may not have started properly."
    echo "Waiting a bit more and checking flash session..."
    sleep 5
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "Flash session is running, but log file not found yet. Continuing anyway..."
        touch "$LOG_FILE"
    else
        echo "Flash session not found. Exiting."
        exit 1
    fi
fi

# Stream output and monitor session status
# Run tail in foreground, monitor session in background
tail -f "$LOG_FILE" 2>/dev/null &
TAIL_PID=$!

# Monitor session in background - kill tail when session ends
(
    while tmux has-session -t "$SESSION_NAME" 2>/dev/null; do
        sleep 1
    done
    # Session ended, wait a moment for final log lines
    sleep 2
    kill "$TAIL_PID" 2>/dev/null
) &
MONITOR_PID=$!

# Wait for tail to finish (will be killed when session ends)
wait "$TAIL_PID" 2>/dev/null || true
kill "$MONITOR_PID" 2>/dev/null || true

echo ''
echo '=== Flash Session Ended ==='
if [ -f "$LOG_FILE" ]; then
    echo ''
    echo 'Last 50 lines:'
    tail -50 "$LOG_FILE"
    echo ''
    echo 'Checking for errors...'
    if tail -100 "$LOG_FILE" | grep -qiE 'error|failed|fatal|exception'; then
        echo ''
        echo '⚠ Errors found:'
        tail -100 "$LOG_FILE" | grep -iE 'error|failed|fatal|exception' | tail -10
    else
        echo 'No errors detected in log'
    fi
fi

