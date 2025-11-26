#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash Jetson device via USB from Raspberry Pi controller
# Usage: flash-usb.sh [--spi-only]
#   --spi-only: Only flash SPI bootloader (for first-time setup)
#
# This script runs on your laptop and executes flashing on the controller

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/controller-common.sh"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  PRE-FLASHING SETUP - Follow these steps carefully${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_step "1. Connect the Jetson device to Raspberry Pi via USB-C cable"
log_info "   - Use the USB-C port on the Jetson board"
log_info "   - Connect to a USB port on the Raspberry Pi"
log_info ""
log_step "2. Put the Jetson device into Forced Recovery Mode:"
log_info "   - Power off the device completely (unplug power adapter)"
log_info "   - Locate the J14 header on the Jetson board"
log_info "   - Find the 'FC_REC' pin and the 'GND' pin on the J14 header"
log_info "   - Short (connect) the FC_REC pin to the GND pin using a jumper wire"
log_info "   - Keep the jumper in place - do not remove it yet"
log_info ""
log_step "3. Power on the device while in recovery mode:"
log_info "   - With the FC_REC to GND jumper still in place, connect the power adapter"
log_info "   - The device should power on and enter recovery mode"
log_info ""
log_step "4. Verify the device is detected on Raspberry Pi:"
log_info "   - The device should appear as an NVIDIA USB device"
log_info "   - Run this command on the Raspberry Pi to check:"
log_info "     lsusb | grep -i nvidia"
log_info "   - You should see 'NVIDIA Corp.' or 'APX' in the output"
log_info ""
log_info "${YELLOW}When you have completed all the steps above, press Enter to continue...${NC}"
read -p "Press Enter to proceed with flashing, or Ctrl+C to cancel..."

# Check if tegraflash archive exists on controller
log_info "Checking for tegraflash archive on controller..."
TEGRAFLASH_ARCHIVE=$(controller_cmd "find $CONTROLLER_TEGRAFLASH_DIR -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | sort -r | head -1" || echo "")

if [ -z "$TEGRAFLASH_ARCHIVE" ]; then
    log_error "Tegraflash archive not found on controller."
    log_info "Push it first: make controller-push-tegraflash"
    exit 1
fi

ARCHIVE_NAME=$(basename "$TEGRAFLASH_ARCHIVE")
log_info "Using tegraflash archive: $ARCHIVE_NAME"

# Determine flash command
FLASH_CMD="./doflash.sh"
if [[ "$*" == *"--spi-only"* ]]; then
    FLASH_CMD="./doflash.sh --spi-only"
    log_info "Flashing SPI bootloader only (first-time setup)"
else
    log_info "Flashing entire device via USB"
fi

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  STARTING FLASH PROCESS${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "This may take several minutes. Please be patient..."
log_info ""

# Execute flashing on controller using Docker
# Source config on controller to get Docker image name
controller_cmd "bash -c '
    source $CONTROLLER_BASE_DIR/config/controller-config.sh
    # Extract tegraflash archive
    TMPDIR=\$(mktemp -d)
    trap \"rm -rf \\\$TMPDIR\" EXIT

    cd \\\$TMPDIR
    tar -xzf $TEGRAFLASH_ARCHIVE

    if [ ! -f \"./doflash.sh\" ]; then
        echo \"ERROR: doflash.sh not found in tegraflash archive\" >&2
        exit 1
    fi

    chmod +x ./*.sh 2>/dev/null || true

    # Run flashing in Docker container
    docker run --rm -it \
        --privileged \
        -v \\\$TMPDIR:/workspace \
        -w /workspace \
        --device=/dev/bus/usb \
        \$DOCKER_IMAGE_NAME:\$DOCKER_IMAGE_TAG bash -c \"
        apt-get update -qq && \
        apt-get install -y -qq device-tree-compiler python3 sudo udev usbutils >/dev/null 2>&1 && \
        $FLASH_CMD
    \"
'"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  FLASH COMPLETED SUCCESSFULLY!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  POST-FLASHING SETUP - Follow these steps to boot your device${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_step "1. Disconnect the USB cable from the Jetson device"
log_info ""
log_step "2. Remove power from the Jetson board"
log_info "   - Unplug the power adapter from the board"
log_info ""
log_step "3. Remove the recovery mode jumper:"
log_info "   - Remove the jumper that shorts FC_REC to GND on the J14 header"
log_info "   - This is required for normal boot operation"
log_info ""
log_step "4. Connect peripherals to the Jetson board:"
log_info "   - Connect a monitor via HDMI or DisplayPort"
log_info "   - Connect a USB keyboard"
log_info "   - Connect a USB mouse (optional)"
log_info ""
log_step "5. Power on the Jetson device:"
log_info "   - Connect the power adapter to the board"
log_info "   - Press the POWER button"
log_info ""
log_step "6. The device should now boot from the flashed image"
log_info "   - You should see boot messages on the connected monitor"
log_info "   - First boot may take longer as the system initializes"
log_info ""

