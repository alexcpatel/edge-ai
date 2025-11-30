#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONTROLLER="${CONTROLLER:-steamdeck}"
require_controller "$CONTROLLER"
get_controller_info "$CONTROLLER"


start_flash() {
    FLASH_MODE="spi-only"
    [ "${1:-}" = "--full" ] && FLASH_MODE="full"

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

    TEGRAFLASH_ARCHIVE=$( (controller_ssh "$CONTROLLER" \
        "find $CURRENT_CONTROLLER_BASE_DIR/tegraflash -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | sort -r | head -1" || echo "") | tr -d '\r\n' | xargs)

    [ -z "$TEGRAFLASH_ARCHIVE" ] && { log_error "No tegraflash archive. Run: make controller-push-tegraflash"; exit 1; }

    controller_ssh "$CONTROLLER" "[ -f '$TEGRAFLASH_ARCHIVE' ]" || {
        log_error "Archive not found on controller: $TEGRAFLASH_ARCHIVE"
        exit 1
    }

    log_info "Using: $(basename "$TEGRAFLASH_ARCHIVE")"

    local_script="$SCRIPT_DIR/on-controller/flash-usb-device.sh"
    remote_script="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/flash-usb-device.sh"

    controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller"
    controller_rsync "$CONTROLLER" "$local_script" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$remote_script"
    controller_ssh "$CONTROLLER" "chmod +x $remote_script"

    log_info "Starting flash..."
    controller_ssh "$CONTROLLER" "bash $remote_script '$TEGRAFLASH_ARCHIVE' '$FLASH_MODE'"

    log_success "USB flash complete!"
}

case "${1:-start}" in
    start) start_flash "${2:-}" ;;
    *) echo "Usage: $0 [start] [--full]"; exit 1 ;;
esac
