#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Yocto build management
# Usage: build-image.sh [start|status|watch|terminate]
#   start:     Start build in tmux session (default)
#   status:    Check if build session is running
#   watch:     Tail the build log file (allows scrolling in local terminal)
#   terminate: Terminate running build session

source "$(dirname "$0")/lib/common.sh"

is_build_running() {
    local ip="$1"
    ssh_cmd "$ip" "tmux has-session -t yocto-build 2>/dev/null" >/dev/null 2>&1
}

start_build() {
    ip=$(get_instance_ip_or_exit)

    # Check if build is already running - fail early if so
    if is_build_running "$ip"; then
        log_error "Build session is already running. Terminate it first with 'make build-terminate'"
        exit 1
    fi

    log_info "Starting Yocto build in tmux session 'yocto-build'..."

    # Configure tmux to disable mouse mode (prevents escape sequences from trackpad scrolling)
    ssh_cmd "$ip" "tmux set -g mouse off 2>/dev/null || true" || true

    # Start build in tmux session using KAS - session will exit when build completes (success or failure)
    # KAS manages its own work directory structure - run from YOCTO_DIR so it creates work dir there
    KAS_CONFIG="${REMOTE_SOURCE_DIR}/build/yocto/config/kas.yml"
    if ! ssh_cmd "$ip" \
        "tmux new-session -d -s yocto-build bash -c \"
             export PATH=\"\$HOME/.local/bin:\$PATH\" && \
             cd $YOCTO_DIR && \
             kas build --update $KAS_CONFIG 2>&1 | tee /tmp/yocto-build.log
             exit \${PIPESTATUS[0]}
         \""; then
        log_error "Failed to start build session via SSH"
        exit 1
    fi

    # Wait a moment and verify the session is actually running
    sleep 2
    if ! is_build_running "$ip"; then
        log_error "Build session failed to start. Check logs:"
        ssh_cmd "$ip" "tail -50 /tmp/yocto-build.log 2>/dev/null || echo 'No log file found'" || true
        exit 1
    fi

    # Start monitor script in background (if not already running)
    MONITOR_SCRIPT="${REMOTE_SOURCE_DIR}/build/yocto/scripts/monitor-build-stop.sh"
    ssh_cmd "$ip" "chmod +x $MONITOR_SCRIPT 2>/dev/null || true" || true
    ssh_cmd "$ip" "pkill -f 'monitor-build-stop.sh' 2>/dev/null || true" || true
    # Start monitor (non-blocking, don't fail if it doesn't start immediately)
    ssh_cmd "$ip" "nohup bash $MONITOR_SCRIPT > /tmp/build-monitor.log 2>&1 &" || true

    log_success "Build started in tmux session 'yocto-build'"
    log_info "Use 'make build-watch' to view progress"
}

check_status() {
    local instance_id state ip
    instance_id=$(get_instance_id)

    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        echo "Instance not found"
        exit 1
    fi

    state=$(get_instance_state "$instance_id")
    if [ "$state" != "running" ]; then
        echo "Instance is $state (not running)"
        echo "No build session can be running when instance is stopped"
        exit 1
    fi

    ip=$(get_instance_ip "$instance_id")
    if [ -z "$ip" ] || [ "$ip" == "None" ]; then
        echo "Could not get instance IP"
        exit 1
    fi

    if is_build_running "$ip"; then
        echo "Build session is running"

        # Get elapsed time of the actual build process (kas or bitbake)
        elapsed=$(ssh_cmd "$ip" \
            "pgrep -f 'bitbake.*$YOCTO_IMAGE\|kas.*build' | head -1 | xargs -I {} ps -o etime= -p {} 2>/dev/null" 2>/dev/null | tr -d ' ' || echo "")

        if [ -n "$elapsed" ]; then
            echo "Elapsed time: $elapsed"
        else
            # Fallback: get elapsed time from tmux session process itself
            elapsed=$(ssh_cmd "$ip" \
                "tmux list-sessions -F '#{session_name} #{pane_pid}' | grep '^yocto-build ' | awk '{print \$2}' | xargs -I {} ps -o etime= -p {} 2>/dev/null" 2>/dev/null | tr -d ' ' || echo "")

            if [ -n "$elapsed" ]; then
                echo "Elapsed time: $elapsed"
            else
                # Last fallback: session is active but we can't get process time
                echo "Build session active (bitbake process not found yet)"
            fi
        fi

        exit 0
    else
        echo "No build session found"

        # Check if there's evidence of an interrupted build
        if ssh_cmd "$ip" "test -f $YOCTO_DIR/build/bitbake.lock 2>/dev/null || test -f $YOCTO_DIR/build*/bitbake.lock 2>/dev/null" 2>/dev/null; then
            echo ""
            echo "⚠ Warning: BitBake lock file exists but no build session is running"
            echo "  Previous build may have been interrupted"
            echo "  Run 'make clean' to clean up and start fresh"
        fi

        # Check for build errors in log file
        if ssh_cmd "$ip" "test -f /tmp/yocto-build.log" 2>/dev/null; then
            echo ""
            echo "=== Recent Build Errors ==="
            local errors
            errors=$(ssh_cmd "$ip" \
                "tail -100 /tmp/yocto-build.log | grep -iE 'error|failed|fatal|exception' | tail -10" 2>/dev/null || echo "")

            if [ -n "$errors" ]; then
                echo "$errors" | sed 's/^/  /'
            else
                # Check last few lines for any indication of failure
                local last_lines
                last_lines=$(ssh_cmd "$ip" "tail -5 /tmp/yocto-build.log" 2>/dev/null || echo "")
                if echo "$last_lines" | grep -qiE "failed|error|aborted"; then
                    echo "$last_lines" | sed 's/^/  /'
                else
                    echo "  (No obvious errors found in recent log output)"
                fi
            fi
        fi

        exit 1
    fi
}

watch_build() {
    ip=$(get_instance_ip_or_exit)

    if ! is_build_running "$ip"; then
        log_error "No build session found. Start a build first with 'make build-image'"
        exit 1
    fi

    log_info "Watching build log (will stop when build completes or errors)"

    # Execute watch script from synced location
    # If SSH fails or is interrupted, that's okay - build is still running
    ssh_cmd "$ip" "bash ${REMOTE_SOURCE_DIR}/build/yocto/scripts/watch-build.sh" || {
        log_info "Watch session ended (build continues in background)"
        exit 0
    }
}

terminate_build() {
    ip=$(get_instance_ip_or_exit)

    if ! is_build_running "$ip"; then
        log_error "No build session found. Nothing to terminate."
        exit 1
    fi

    log_info "Terminating build session..."
    ssh_cmd "$ip" "tmux kill-session -t yocto-build 2>/dev/null || true" || true

    # Clean up bitbake processes and lock files after terminating
    log_info "Cleaning up BitBake processes and lock files..."
    ssh_cmd "$ip" "pkill -f 'bitbake.*server' 2>/dev/null || true" || true
    ssh_cmd "$ip" "pkill -f 'bitbake.*-m' 2>/dev/null || true" || true
    ssh_cmd "$ip" "find $YOCTO_DIR -name 'bitbake.lock' -type f -delete 2>/dev/null || true" || true
    ssh_cmd "$ip" "find $YOCTO_DIR -name 'bitbake.sock' -type f -delete 2>/dev/null || true" || true

    log_success "Build session terminated and cleaned up"
}

set_auto_stop() {
    ip=$(get_instance_ip_or_exit)
    FLAG_FILE="/tmp/auto-stop-instance"
    ssh_cmd "$ip" "touch $FLAG_FILE"
    log_success "Auto-stop enabled (instance will stop when build ends)"
}

unset_auto_stop() {
    ip=$(get_instance_ip_or_exit)
    FLAG_FILE="/tmp/auto-stop-instance"
    ssh_cmd "$ip" "rm -f $FLAG_FILE"
    log_success "Auto-stop disabled"
}

check_auto_stop() {
    ip=$(get_instance_ip_or_exit)
    FLAG_FILE="/tmp/auto-stop-instance"
    if ssh_cmd "$ip" "test -f $FLAG_FILE" 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

ACTION="${1:-start}"

case "$ACTION" in
    start)
        start_build
        ;;
    status)
        check_status
        ;;
    watch)
        watch_build
        ;;
    terminate)
        terminate_build
        ;;
    set-auto-stop)
        set_auto_stop
        ;;
    unset-auto-stop)
        unset_auto_stop
        ;;
    check-auto-stop)
        check_auto_stop
        ;;
    *)
        echo "Usage: $0 [start|status|watch|terminate|set-auto-stop|unset-auto-stop|check-auto-stop]"
        echo "  start          - Start build in tmux session (default)"
        echo "  status         - Check if build session is running"
        echo "  watch          - Tail the build log file (allows scrolling in local terminal)"
        echo "  terminate      - Terminate running build session"
        echo "  set-auto-stop  - Enable auto-stop (instance stops when build ends)"
        echo "  unset-auto-stop - Disable auto-stop"
        echo "  check-auto-stop - Check if auto-stop is enabled"
        exit 1
        ;;
esac

