#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash Jetson device via USB
# Usage: flash-usb.sh [--spi-only]
#   --spi-only: Only flash SPI bootloader (for first-time setup)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/build/remote/config/aws-config.sh"
source "$REPO_ROOT/build/yocto/config/yocto-config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_error() { echo -e "${RED}$*${NC}"; }

# Check if running on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    USE_DOCKER=true
    log_info "Detected macOS - will use Docker for USB access"
else
    USE_DOCKER=false
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
log_info "IMPORTANT:"
log_info "  1. Connect Jetson to computer via USB cable"
log_info "  2. Put device in Forced Recovery Mode:"
log_info "     - Power off device"
log_info "     - Press and hold RECOVERY button"
log_info "     - While holding, press and release POWER button"
log_info "     - Release RECOVERY button"
log_info "  3. Device should appear in recovery mode"
log_info ""
read -p "Press Enter when device is in recovery mode, or Ctrl+C to cancel..."

if [ "$USE_DOCKER" = true ]; then
    log_info "Using Docker for USB flashing on macOS..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    # On macOS, USB devices appear as /dev/tty.usbmodem* or /dev/cu.usbmodem*
    # We need to pass these to Docker, but Docker on macOS has limited USB support
    # The tegraflash tools may need direct USB access which is complex on macOS
    log_info "Running flash command in Docker container..."
    log_info "Note: USB passthrough on macOS Docker may require additional setup"
    log_info "If this fails, you may need to run on a Linux machine or use a VM"
    
    # Try to find USB device
    USB_DEVICE=$(ls /dev/tty.usbmodem* /dev/cu.usbmodem* 2>/dev/null | head -1 || echo "")
    
    if [ -n "$USB_DEVICE" ]; then
        log_info "Found USB device: $USB_DEVICE"
    fi
    
    # Run in Docker - note: USB access on macOS Docker is limited
    # May need to use Docker Desktop with USB passthrough extension or run on Linux
    docker run --rm -it \
        --privileged \
        -v "$TMPDIR:/workspace" \
        -w /workspace \
        ubuntu:22.04 bash -c "
        apt-get update -qq && \
        apt-get install -y -qq device-tree-compiler python3 sudo udev usbutils >/dev/null 2>&1 && \
        $FLASH_CMD
    "
else
    log_info "Running flash command directly..."
    sudo $FLASH_CMD
fi

log_success "Flash completed successfully!"

