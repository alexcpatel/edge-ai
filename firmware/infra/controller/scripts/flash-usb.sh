#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONTROLLER="${CONTROLLER:-steamdeck}"
require_controller "$CONTROLLER"
get_controller_info "$CONTROLLER"

SESSION="usb-flash"
LOG_FILE="/tmp/usb-flash.log"

is_flash_running() {
    ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" \
        "tmux has-session -t $SESSION 2>/dev/null" >/dev/null 2>&1
}

start_flash() {
    FLASH_MODE="spi-only"
    [ "${1:-}" = "--full" ] && FLASH_MODE="full"

    is_flash_running && { log_error "Flash already running. Use 'make controller-flash-usb-terminate' first"; exit 1; }

    log_info "=== USB Flash Setup ==="
    [ "$FLASH_MODE" = "full" ] && log_info "Mode: FULL (bootloader + rootfs)" \
        || log_info "Mode: SPI-only (bootloader). Use --full for complete flash."
    echo ""
    log_info "1. Connect Jetson to controller via USB-C"
    log_info "2. Put Jetson in recovery mode (short FC_REC to GND, then power on)"
    log_info "3. Verify: lsusb | grep -i nvidia"
    echo ""
    read -p "Press Enter when ready, Ctrl+C to cancel..."

    check_controller_connection "$CONTROLLER"

    controller_ssh "$CONTROLLER" "command -v tmux >/dev/null 2>&1" || {
        log_error "tmux is not installed on controller. Run: make firmware-controller-setup C=$CONTROLLER"
        exit 1
    }

    TEGRAFLASH_ARCHIVE=$( (controller_ssh "$CONTROLLER" \
        "find $CURRENT_CONTROLLER_BASE_DIR/tegraflash -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | sort -r | head -1" || echo "") | tr -d '\r\n' | xargs)

    [ -z "$TEGRAFLASH_ARCHIVE" ] && { log_error "No tegraflash archive. Run: make controller-push-tegraflash"; exit 1; }

    controller_ssh "$CONTROLLER" "[ -f '$TEGRAFLASH_ARCHIVE' ]" || {
        log_error "Archive not found on controller: $TEGRAFLASH_ARCHIVE"
        exit 1
    }

    log_info "Using: $(basename "$TEGRAFLASH_ARCHIVE")"

    local_script="$SCRIPT_DIR/on-controller/flash-device.sh"
    remote_script="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/flash-device.sh"
    watch_script="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/watch-flash.sh"

    controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller"
    controller_rsync "$CONTROLLER" "$local_script" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$remote_script"
    controller_ssh "$CONTROLLER" "chmod +x $remote_script"

    local watch_local="$SCRIPT_DIR/on-controller/watch-flash.sh"
    [ -f "$watch_local" ] && {
        controller_rsync "$CONTROLLER" "$watch_local" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$watch_script"
        controller_ssh "$CONTROLLER" "chmod +x $watch_script"
    }

    log_info "Starting flash in persistent session..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" \
        "tmux set -g mouse off 2>/dev/null || true" >/dev/null 2>&1 || true
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" \
        "tmux new-session -d -s $SESSION bash -c 'LOG_FILE=$LOG_FILE bash $remote_script \"$TEGRAFLASH_ARCHIVE\" \"$FLASH_MODE\"'" >/dev/null 2>&1 || {
        log_error "Failed to start flash"; exit 1
    }

    for _ in {1..3}; do is_flash_running && break; sleep 0.5; done
    is_flash_running || { log_error "Flash failed to start"; ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" "tail -50 $LOG_FILE" 2>/dev/null || true; exit 1; }

    log_success "Flash started in persistent session"
    log_info "Use 'make controller-flash-usb-watch' to view progress"
}

check_status() {
    check_controller_connection "$CONTROLLER"

    if is_flash_running; then
        echo "Flash session is running"
        local elapsed
        elapsed=$(controller_ssh "$CONTROLLER" "pgrep -f 'doflash.sh\|flash-device.sh' | head -1 | \
            xargs -I {} ps -o etime= -p {} 2>/dev/null | tr -d ' '" 2>/dev/null || echo "")
        [ -n "$elapsed" ] && echo "Elapsed: $elapsed" || echo "Flash starting..."
        controller_ssh "$CONTROLLER" "tail -5 $LOG_FILE 2>/dev/null" || true
    else
        echo "No flash session found"
        if controller_ssh "$CONTROLLER" "test -f $LOG_FILE" 2>/dev/null; then
            echo ""
            echo "Last log output:"
            controller_ssh "$CONTROLLER" "tail -20 $LOG_FILE" || true
        fi
    fi
}

watch_flash() {
    check_controller_connection "$CONTROLLER"
    is_flash_running || { log_error "No flash session. Start with 'make controller-flash-usb'"; exit 1; }
    log_info "Watching flash log..."
    controller_ssh "$CONTROLLER" "bash $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/watch-flash.sh" || {
        log_info "Watch ended (flash continues in background)"; exit 0
    }
}

terminate_flash() {
    check_controller_connection "$CONTROLLER"
    is_flash_running || { log_error "No flash session to terminate"; exit 1; }
    log_info "Terminating flash..."
    controller_ssh "$CONTROLLER" "tmux kill-session -t $SESSION 2>/dev/null || true" || true
    controller_ssh "$CONTROLLER" "pkill -f 'doflash.sh' 2>/dev/null || true" || true
    log_success "Flash terminated"
}

case "${1:-start}" in
    start) start_flash "${2:-}" ;;
    status) check_status ;;
    watch) watch_flash ;;
    terminate) terminate_flash ;;
    *) echo "Usage: $0 [start|status|watch|terminate] [--full]"; exit 1 ;;
esac
