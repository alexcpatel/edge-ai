#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Watch build log and stop when build completes or errors
# This script runs on the remote EC2 instance
# Exit code: 0 = build succeeded, 1 = build failed

LOG_FILE="/tmp/yocto-build.log"
SESSION_NAME="yocto-build"
EXIT_CODE_FILE="/tmp/yocto-build-exit"

# Wait for log file to exist (build might have just started)
# Add timeout to prevent infinite waiting
wait_count=0
max_wait=30
while [ ! -f "$LOG_FILE" ] && [ $wait_count -lt $max_wait ]; do
    sleep 1
    wait_count=$((wait_count + 1))
done

if [ ! -f "$LOG_FILE" ]; then
    echo "Warning: Log file not found after waiting. Build may not have started properly."
    echo "Waiting a bit more and checking build session..."
    sleep 5
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "Build session is running, but log file not found yet. Continuing anyway..."
        # Create empty log file so tail doesn't fail
        touch "$LOG_FILE"
    else
        echo "Build session not found. Exiting."
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

# Check build exit code (written by run-build.sh)
if [ -f "$EXIT_CODE_FILE" ]; then
    BUILD_EXIT=$(cat "$EXIT_CODE_FILE")
    exit "$BUILD_EXIT"
fi

# Fallback: check log for error indicators
if grep -q "^ERROR:" "$LOG_FILE" 2>/dev/null; then
    exit 1
fi

exit 0
