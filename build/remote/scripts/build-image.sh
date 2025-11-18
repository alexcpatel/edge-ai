#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Yocto build management
# Usage: build-image.sh [start|status|attach|watch]
#   start:  Start build in tmux session (default)
#   status: Check if build session is running
#   attach: Attach to running build session to view logs
#   watch:  Tail the build log file (allows scrolling in local terminal)

source "$(dirname "$0")/lib/common.sh"

is_build_running() {
    local ip="$1"
    ssh_cmd "$ip" "tmux has-session -t yocto-build 2>/dev/null"
}

start_build() {
    ip=$(get_instance_ip_or_exit)

    # Kill any existing session
    if is_build_running "$ip"; then
        log_info "Killing existing build session..."
        ssh_cmd "$ip" "tmux kill-session -t yocto-build 2>/dev/null || true"
        sleep 1
    fi

    log_info "Starting Yocto build in tmux session 'yocto-build'..."

    # Configure tmux to disable mouse mode (prevents escape sequences from trackpad scrolling)
    ssh_cmd "$ip" "tmux set -g mouse off 2>/dev/null || true"

    # Start build in tmux session - session will exit when build completes (success or failure)
    ssh_cmd "$ip" \
        "tmux new-session -d -s yocto-build bash -c \"
             cd $YOCTO_DIR && \
             source poky/oe-init-build-env build && \
             bitbake $YOCTO_IMAGE 2>&1 | tee /tmp/yocto-build.log
             exit \${PIPESTATUS[0]}
         \""

    log_success "Build started in tmux session 'yocto-build'"
    log_info "Use 'make build-attach' to view progress (Ctrl+B then D to detach)"
}

check_status() {
    ip=$(get_instance_ip_or_exit)

    if is_build_running "$ip"; then
        echo "Build session is running"

        # Get elapsed time of the actual bitbake process (not tmux session)
        elapsed=$(ssh_cmd "$ip" \
            "pgrep -f 'bitbake.*$YOCTO_IMAGE' | head -1 | xargs -I {} ps -o etime= -p {} 2>/dev/null" | tr -d ' ' || echo "")

        if [ -n "$elapsed" ]; then
            echo "Elapsed time: $elapsed"
        else
            # Fallback: check if build is in progress but bitbake not found yet
            echo "Build session active (bitbake process not found yet)"
        fi

        exit 0
    else
        echo "No build session found"

        # Check if there's evidence of an interrupted build
        if ssh_cmd "$ip" "test -f $YOCTO_DIR/build/bitbake.lock" 2>/dev/null; then
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

attach_build() {
    ip=$(get_instance_ip_or_exit)

    if ! is_build_running "$ip"; then
        log_error "No build session found. Start a build first with 'make build-image'"
        exit 1
    fi

    # Ensure mouse mode is disabled before attaching
    ssh_cmd "$ip" "tmux set -g mouse off 2>/dev/null || true"

    log_info "Attaching to build session (Ctrl+B then D to detach, or Ctrl+B then [ to scroll)"
    ssh_cmd "$ip" -t "tmux attach-session -t yocto-build"
}

watch_build() {
    ip=$(get_instance_ip_or_exit)

    if ! is_build_running "$ip"; then
        log_error "No build session found. Start a build first with 'make build-image'"
        exit 1
    fi

    log_info "Watching build log (will stop when build completes or errors)"

    # Execute watch script from synced location
    ssh_cmd "$ip" "bash ${REMOTE_SOURCE_DIR}/build/yocto/scripts/watch-build.sh"
}

ACTION="${1:-start}"

case "$ACTION" in
    start)
        start_build
        ;;
    status)
        check_status
        ;;
    attach)
        attach_build
        ;;
    watch)
        watch_build
        ;;
    *)
        echo "Usage: $0 [start|status|attach|watch]"
        echo "  start   - Start build in tmux session (default)"
        echo "  status  - Check if build session is running"
        echo "  attach  - Attach to running build session to view logs"
        echo "  watch   - Tail the build log file (allows scrolling in local terminal)"
        exit 1
        ;;
esac

