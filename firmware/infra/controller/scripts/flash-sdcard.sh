#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONTROLLER="${CONTROLLER:-steamdeck}"
require_controller "$CONTROLLER"
get_controller_info "$CONTROLLER"

log_info "=== SD Card Flash ==="

check_controller_connection "$CONTROLLER"

TEGRAFLASH_ARCHIVE=$( (controller_ssh "$CONTROLLER" \
    "find $CURRENT_CONTROLLER_BASE_DIR/tegraflash -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | sort -r | head -1" || echo "") | tr -d '\r\n' | xargs)

[ -z "$TEGRAFLASH_ARCHIVE" ] && { log_error "No tegraflash archive. Run: make controller-push-tegraflash"; exit 1; }

log_info "Using: $(basename "$TEGRAFLASH_ARCHIVE")"

local_script="$SCRIPT_DIR/on-controller/flash-sdcard-device.sh"
remote_script="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/flash-sdcard-device.sh"

controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller"
controller_rsync "$CONTROLLER" "$local_script" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$remote_script"
controller_ssh "$CONTROLLER" "chmod +x $remote_script"

SD_DEVICE="${1:-}"
[ -n "$SD_DEVICE" ] && controller_ssh "$CONTROLLER" "bash $remote_script '$TEGRAFLASH_ARCHIVE' '$SD_DEVICE'" \
    || controller_ssh "$CONTROLLER" "bash $remote_script '$TEGRAFLASH_ARCHIVE'"

log_success "SD card flash complete!"
