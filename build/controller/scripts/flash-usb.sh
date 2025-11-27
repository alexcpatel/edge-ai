#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash Jetson device via USB from Raspberry Pi controller
# This script runs on your laptop and executes flashing on the controller

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Save absolute paths before sourcing (which may change SCRIPT_DIR)
FLASH_SCRIPT_LOCAL="$(cd "$SCRIPT_DIR" && pwd)/on-controller/flash-device.sh"

source "$SCRIPT_DIR/lib/controller-common.sh"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  PRE-FLASHING SETUP - Follow these steps carefully${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "${YELLOW}NOTE: This will only flash the bootloader to SPI flash.${NC}"
log_info "${YELLOW}You will need to flash the SD card separately using dosdcard.sh${NC}"
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

# Flash command
FLASH_CMD="./doflash.sh --spi-only"
log_info "Flashing bootloader to SPI flash only (--spi-only)"
log_info "This will:"
log_info "  - Update the bootloader in SPI flash (QSPI-NOR)"
log_info "  - NOT flash the root filesystem (flash SD card separately)"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  STARTING FLASH PROCESS${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "This should take approximately 15 minutes (much faster than full flash)..."
log_info ""

# Deploy flash script to controller if needed
FLASH_SCRIPT_REMOTE="$CONTROLLER_BASE_DIR/scripts/on-controller/flash-device.sh"

# Verify script exists
if [ ! -f "$FLASH_SCRIPT_LOCAL" ]; then
    log_error "Flash script not found: $FLASH_SCRIPT_LOCAL"
    exit 1
fi

log_step "Deploying flash script to controller..."
controller_cmd "mkdir -p $CONTROLLER_BASE_DIR/scripts/on-controller"
controller_rsync "$FLASH_SCRIPT_LOCAL" "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}:$FLASH_SCRIPT_REMOTE"
controller_cmd "chmod +x $FLASH_SCRIPT_REMOTE"

# Execute flashing on controller
log_step "Executing flash on controller..."
log_info "Archive path: $TEGRAFLASH_ARCHIVE"
controller_cmd "bash $FLASH_SCRIPT_REMOTE '$TEGRAFLASH_ARCHIVE'"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  FLASH COMPLETED SUCCESSFULLY!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  POST-FLASHING SETUP - Next Steps${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_step "1. Bootloader flash complete!"
log_info "   - The bootloader has been flashed to SPI flash"
log_info ""
log_step "2. Next: Flash the SD card separately"
log_info "   - Use dosdcard.sh to create and flash the SD card image"
log_info "   - The SD card contains the root filesystem"
log_info ""
log_step "3. After SD card is flashed:"
log_info "   - Remove the recovery mode jumper (FC_REC to GND)"
log_info "   - Insert the flashed SD card into the Jetson board"
log_info "   - Connect peripherals (monitor, keyboard, etc.)"
log_info "   - Power on the device"
log_info ""

