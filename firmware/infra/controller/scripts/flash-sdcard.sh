#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash SD card with Yocto image from Steam Deck controller
# This script runs on your laptop and executes SD card flashing on the controller
# Usage: flash-sdcard.sh [SD_CARD_DEVICE]
#   If SD_CARD_DEVICE is not provided, will prompt for selection on controller

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Save absolute paths before sourcing
FLASH_SDCARD_SCRIPT_LOCAL="$(cd "$SCRIPT_DIR" && pwd)/on-controller/flash-sdcard-device.sh"

# Use steamdeck controller for flash operations
export CONTROLLER_NAME="steamdeck"

source "$SCRIPT_DIR/lib/controller-common.sh"

get_controller_info "steamdeck"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  SD CARD FLASHING SETUP${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Check if controller is set up and has required packages
log_step "Checking controller setup..."
# Check if required packages are installed (check a few key ones)
KEY_PACKAGES=("device-tree-compiler" "python3" "python3-yaml" "gdisk" "zstd")
MISSING_COUNT=0
for pkg in "${KEY_PACKAGES[@]}"; do
    if ! controller_cmd "steamdeck" "dpkg -l | grep -q \"^ii.*$pkg \" 2>/dev/null" 2>/dev/null; then
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done

# Also check for i386 architecture support
if ! controller_cmd "steamdeck" "dpkg --print-foreign-architectures | grep -q i386 2>/dev/null" 2>/dev/null; then
    MISSING_COUNT=$((MISSING_COUNT + 1))
fi

if [ $MISSING_COUNT -gt 0 ]; then
    log_info "Controller missing required packages. Setting up controller..."
    SETUP_SCRIPT_LOCAL="$(cd "$SCRIPT_DIR" && pwd)/on-controller/setup.sh"
    SETUP_SCRIPT_REMOTE="/tmp/setup-controller-$$.sh"

    # Copy and run setup script
    controller_rsync "steamdeck" "$SETUP_SCRIPT_LOCAL" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}:${SETUP_SCRIPT_REMOTE}"
    controller_cmd "steamdeck" "bash $SETUP_SCRIPT_REMOTE"
    controller_cmd "steamdeck" "rm -f $SETUP_SCRIPT_REMOTE"

    log_success "Controller setup complete"
else
    log_success "Controller is properly set up"
fi

# Check if tegraflash archive exists on controller
log_step "Checking for tegraflash archive on controller..."
TEGRAFLASH_ARCHIVE=$(controller_cmd "steamdeck" "find $CURRENT_CONTROLLER_BASE_DIR/tegraflash -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | sort -r | head -1" || echo "")

if [ -z "$TEGRAFLASH_ARCHIVE" ]; then
    log_error "Tegraflash archive not found on controller."
    log_info "Push it first: make controller-push-tegraflash"
    exit 1
fi

ARCHIVE_NAME=$(basename "$TEGRAFLASH_ARCHIVE")
log_info "Using tegraflash archive: $ARCHIVE_NAME"

# Deploy flash script to controller
FLASH_SDCARD_SCRIPT_REMOTE="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/flash-sdcard-device.sh"

# Verify script exists
if [ ! -f "$FLASH_SDCARD_SCRIPT_LOCAL" ]; then
    log_error "Flash SD card script not found: $FLASH_SDCARD_SCRIPT_LOCAL"
    exit 1
fi

log_step "Deploying flash SD card script to controller..."
controller_cmd "steamdeck" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller"
controller_rsync "steamdeck" "$FLASH_SDCARD_SCRIPT_LOCAL" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}:$FLASH_SDCARD_SCRIPT_REMOTE"
controller_cmd "steamdeck" "chmod +x $FLASH_SDCARD_SCRIPT_REMOTE"

# Execute flashing on controller
log_step "Executing SD card flash on controller..."
log_info "Archive path: $TEGRAFLASH_ARCHIVE"
SD_CARD_DEVICE="${1:-}"
if [ -n "$SD_CARD_DEVICE" ]; then
    controller_cmd "steamdeck" "bash $FLASH_SDCARD_SCRIPT_REMOTE '$TEGRAFLASH_ARCHIVE' '$SD_CARD_DEVICE'"
else
    controller_cmd "steamdeck" "bash $FLASH_SDCARD_SCRIPT_REMOTE '$TEGRAFLASH_ARCHIVE'"
fi

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  SD CARD FLASH COMPLETED SUCCESSFULLY!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

