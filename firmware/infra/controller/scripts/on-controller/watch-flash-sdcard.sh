#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

LOG_FILE="/tmp/sdcard-flash.log"
SESSION_NAME="sdcard-flash"

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

tail -f "$LOG_FILE" 2>/dev/null &
TAIL_PID=$!

(
    while tmux has-session -t "$SESSION_NAME" 2>/dev/null; do
        sleep 1
    done
    sleep 2
    kill "$TAIL_PID" 2>/dev/null
) &
MONITOR_PID=$!

wait "$TAIL_PID" 2>/dev/null || true
kill "$MONITOR_PID" 2>/dev/null || true

echo ''
echo '=== Flash Session Ended ==='
if [ -f "$LOG_FILE" ]; then
    echo ''
    echo 'Last 50 lines:'
    tail -50 "$LOG_FILE"
fi

