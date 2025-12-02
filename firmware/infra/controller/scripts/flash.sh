#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/common.sh"
source "$REPO_ROOT/firmware/infra/ec2/scripts/lib/common.sh"

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

push_tegraflash() {
    log_info "Syncing tegraflash from EC2 to controller..."

    local ip
    ip=$(get_instance_ip_or_exit)

    local ARTIFACTS_DIR="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"
    local ARCHIVE
    ARCHIVE=$(ssh_cmd "$ip" "ls -t $ARTIFACTS_DIR/*.tegraflash.tar.gz 2>/dev/null | head -1" || echo "")

    [ -z "$ARCHIVE" ] && { log_error "No tegraflash archive on EC2. Build first: make firmware-build"; exit 1; }

    local ARCHIVE_NAME
    ARCHIVE_NAME=$(basename "$ARCHIVE")
    log_info "Found: $ARCHIVE_NAME"

    controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/tegraflash"
    controller_ssh "$CONTROLLER" "rm -f $CURRENT_CONTROLLER_BASE_DIR/tegraflash/*.tegraflash.tar.gz"

    local REMOTE_ARCHIVE="$CURRENT_CONTROLLER_BASE_DIR/tegraflash/$ARCHIVE_NAME"
    local TMP_FILE
    TMP_FILE=$(mktemp)
    trap "rm -f $TMP_FILE" EXIT

    log_info "Downloading from EC2..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${EC2_USER}@${ip}:${ARCHIVE}" "$TMP_FILE"

    file "$TMP_FILE" | grep -q "gzip" || { log_error "Not a valid gzip archive"; exit 1; }

    log_info "Uploading to controller..."
    controller_rsync "$CONTROLLER" "$TMP_FILE" \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$REMOTE_ARCHIVE"

    rm -f "$TMP_FILE"
    trap - EXIT
}

wait_for_nvidia_device() {
    log_info "Waiting for NVIDIA USB device on controller..."
    log_info "(Connect Jetson via USB-C and put in recovery mode)"
    
    local count=0
    while true; do
        if controller_ssh "$CONTROLLER" "lsusb 2>/dev/null | grep -qi nvidia" 2>/dev/null; then
            log_success "NVIDIA device detected"
            return 0
        fi
        count=$((count + 1))
        if [ $((count % 10)) -eq 0 ]; then
            log_info "Still waiting... (${count}s)"
        fi
        sleep 1
    done
}

start_flash() {
    FLASH_MODE="${1:-bootloader}"
    [ -z "$FLASH_MODE" ] && FLASH_MODE="bootloader"
    [[ "$FLASH_MODE" == "bootloader" || "$FLASH_MODE" == "rootfs" ]] || {
        log_error "Invalid mode: $FLASH_MODE. Must be 'bootloader' or 'rootfs'"
        exit 1
    }

    is_flash_running && { log_error "Flash already running. Use 'make firmware-controller-flash-terminate' first"; exit 1; }

    check_controller_connection "$CONTROLLER"

    push_tegraflash

    log_info "=== USB Flash ==="
    [ "$FLASH_MODE" = "rootfs" ] && log_info "Mode: Rootfs (NVMe)" \
        || log_info "Mode: Bootloader (SPI)"

    wait_for_nvidia_device

    controller_ssh "$CONTROLLER" "command -v tmux >/dev/null 2>&1" || {
        log_error "tmux is not installed on controller. Run: make firmware-controller-setup C=$CONTROLLER"
        exit 1
    }

    TEGRAFLASH_ARCHIVE=$( (controller_ssh "$CONTROLLER" \
        "ls -t $CURRENT_CONTROLLER_BASE_DIR/tegraflash/*.tegraflash.tar.gz 2>/dev/null | head -1" || echo "") | tr -d '\r\n' | xargs)

    [ -z "$TEGRAFLASH_ARCHIVE" ] && { log_error "No tegraflash archive found on controller"; exit 1; }

    controller_ssh "$CONTROLLER" "[ -f '$TEGRAFLASH_ARCHIVE' ]" || {
        log_error "Archive not found on controller: $TEGRAFLASH_ARCHIVE"
        exit 1
    }

    log_info "Using: $(basename "$TEGRAFLASH_ARCHIVE")"

    local_script="$SCRIPT_DIR/on-controller/flash-device.sh"
    remote_script="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/flash-device.sh"
    watch_script="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/watch-flash-usb.sh"

    controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller"
    controller_rsync "$CONTROLLER" "$local_script" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$remote_script"
    controller_ssh "$CONTROLLER" "chmod +x $remote_script"

    local watch_local="$SCRIPT_DIR/on-controller/watch-flash-usb.sh"
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
    log_info "Use 'make firmware-controller-flash-watch' to view progress"
}

check_status() {
    check_controller_connection "$CONTROLLER"

    if is_flash_running; then
        echo "Flash session is running"
        local elapsed
        elapsed=$(controller_ssh "$CONTROLLER" "pgrep -f 'doflash.sh|doexternal.sh|initrd-flash|flash-device.sh' | head -1 | \
            xargs -I {} ps -o etime= -p {} 2>/dev/null | tr -d ' '" 2>/dev/null || echo "")
        [ -n "$elapsed" ] && echo "Elapsed: $elapsed" || echo "Flash starting..."
        controller_ssh "$CONTROLLER" "tail -5 $LOG_FILE 2>/dev/null" || true
    else
        echo "No flash session found"
    fi
}

watch_flash() {
    check_controller_connection "$CONTROLLER"
    is_flash_running || { log_error "No flash session. Start with 'make firmware-controller-flash'"; exit 1; }
    log_info "Watching flash log..."
    controller_ssh "$CONTROLLER" "bash $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/watch-flash-usb.sh" || {
        log_info "Watch ended (flash continues in background)"; exit 0
    }
}

terminate_flash() {
    check_controller_connection "$CONTROLLER"
    is_flash_running || { log_error "No flash session to terminate"; exit 1; }
    log_info "Terminating flash..."
    controller_ssh "$CONTROLLER" "tmux kill-session -t $SESSION 2>/dev/null || true" || true
    controller_ssh "$CONTROLLER" "pkill -f 'doflash.sh\|doexternal.sh' 2>/dev/null || true" || true
    log_success "Flash terminated"
}

case "${1:-start}" in
    start) start_flash "${2:-}" ;;
    status) check_status ;;
    watch) watch_flash ;;
    terminate) terminate_flash ;;
    *) echo "Usage: $0 [start|status|watch|terminate] [bootloader|rootfs]"; exit 1 ;;
esac
