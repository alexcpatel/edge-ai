#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Watch build log and stop when build completes or errors
# This script runs on the remote EC2 instance

LOG_FILE="/tmp/yocto-build.log"
SESSION_NAME="yocto-build"

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
wait "$TAIL_PID" 2>/dev/null
kill "$MONITOR_PID" 2>/dev/null

# Show final output
echo ''
echo '=== Build Session Ended ==='
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
    fi
fi

