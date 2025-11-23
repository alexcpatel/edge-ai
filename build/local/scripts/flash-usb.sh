#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash Jetson device via USB (macOS only)
# Usage: flash-usb.sh [--spi-only]
#   --spi-only: Only flash SPI bootloader (for first-time setup)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/build/remote/config/aws-config.sh"
source "$REPO_ROOT/build/yocto/config/yocto-config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_error() { echo -e "${RED}$*${NC}"; }
log_step() { echo -e "${BLUE}${BOLD}→ $*${NC}"; }

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script only works on macOS"
    exit 1
fi

# Find tegraflash archive locally
LOCAL_TEGRAFLASH_DIR="$REPO_ROOT/build/local/tegraflash"
TEGRAFLASH_ARCHIVE=$(find "$LOCAL_TEGRAFLASH_DIR" -maxdepth 1 -name "*.tegraflash.tar.gz" -type f 2>/dev/null | sort -r | head -1)

if [ -z "$TEGRAFLASH_ARCHIVE" ]; then
    log_error "Tegraflash archive not found locally."
    log_info "Download it first: make download-tegraflash"
    exit 1
fi

log_info "Using tegraflash archive: $(basename "$TEGRAFLASH_ARCHIVE")"

# Create temporary directory for extraction
TMPDIR=$(mktemp -d)
trap 'log_info "Cleaning up..."; rm -rf "$TMPDIR"' EXIT

log_info "Extracting tegraflash archive..."
tar -xzf "$TEGRAFLASH_ARCHIVE" -C "$TMPDIR"

cd "$TMPDIR"

if [ ! -f "./doflash.sh" ]; then
    log_error "doflash.sh not found in tegraflash archive"
    exit 1
fi

chmod +x ./*.sh 2>/dev/null || true

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
log_info "${BOLD}  PRE-FLASHING SETUP - Follow these steps carefully${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_step "1. Connect the Jetson device to your Mac via USB-C cable"
log_info "   - Use the USB-C port on the Jetson board"
log_info "   - Connect to any USB-C port on your Mac"
log_info ""
log_step "2. Put the Jetson device into Forced Recovery Mode:"
log_info "   - Power off the device completely (unplug power adapter)"
log_info "   - Locate the J14 header on the Jetson board"
log_info "   - Find the 'FC_REC' pin and the 'GND' pin on the J14 header"
log_info "   - Short (connect) the FC_REC pin to the GND pin using a jumper wire or jumper cap"
log_info "   - Keep the jumper in place - do not remove it yet"
log_info ""
log_step "3. Power on the device while in recovery mode:"
log_info "   - With the FC_REC to GND jumper still in place, connect the power adapter"
log_info "   - The device should power on and enter recovery mode"
log_info ""
log_step "4. Verify the device is in recovery mode:"
log_info "   - The device should appear as an NVIDIA USB device"
log_info "   - You can verify by running: ioreg -p IOUSB -w0 | grep -i nvidia"
log_info "   - Or check for USB device ID 0955:7523 (NVIDIA Corp. APX)"
log_info ""
log_info "${YELLOW}When you have completed all the steps above, press Enter to continue...${NC}"
read -p "Press Enter to proceed with flashing, or Ctrl+C to cancel..."

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  STARTING FLASH PROCESS${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running. Please start Docker Desktop."
    exit 1
fi

log_info "Using Docker for USB flashing on macOS..."
log_info "This may take several minutes. Please be patient..."
log_info ""

# Run in Docker
docker run --rm -it \
    --privileged \
    -v "$TMPDIR:/workspace" \
    -w /workspace \
    ubuntu:22.04 bash -c "
    apt-get update -qq && \
    apt-get install -y -qq device-tree-compiler python3 sudo udev usbutils >/dev/null 2>&1 && \
    $FLASH_CMD
"

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
log_info "${YELLOW}Press Enter when you're ready to exit, or Ctrl+C to cancel...${NC}"
read -p ""

