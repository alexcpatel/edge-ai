#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash SD card with Yocto image
# Usage: flash-sdcard.sh [SD_CARD_DEVICE]
#   If SD_CARD_DEVICE is not provided, will create SD card image file

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
    log_info "Detected macOS - will use Docker for device access"
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

if [ ! -f "./dosdcard.sh" ]; then
    log_error "dosdcard.sh not found in tegraflash archive"
    exit 1
fi

chmod +x ./*.sh 2>/dev/null || true

SD_CARD_DEVICE="${1:-}"

if [ -z "$SD_CARD_DEVICE" ]; then
    # Create SD card image file
    log_info "Creating SD card image file..."
    
    if [ "$USE_DOCKER" = true ]; then
        docker run --rm -it \
            -v "$TMPDIR:/workspace" \
            -w /workspace \
            ubuntu:22.04 bash -c "
            apt-get update -qq && \
            apt-get install -y -qq device-tree-compiler >/dev/null 2>&1 && \
            ./dosdcard.sh
        "
    else
        if ! command -v dtc >/dev/null 2>&1; then
            log_error "device-tree-compiler (dtc) not found. Install it first."
            exit 1
        fi
        ./dosdcard.sh
    fi
    
    SDCARD_IMG=$(find . -maxdepth 1 -name "*.sdcard" -type f | head -1)
    
    if [ -z "$SDCARD_IMG" ]; then
        log_error "SD card image not created"
        exit 1
    fi
    
    # Move to Downloads folder
    DOWNLOADS_DIR="$HOME/Downloads"
    mkdir -p "$DOWNLOADS_DIR"
    mv "$SDCARD_IMG" "$DOWNLOADS_DIR/"
    
    log_success "SD card image created: $DOWNLOADS_DIR/$(basename "$SDCARD_IMG")"
    log_info "Flash it to SD card using:"
    log_info "  gunzip -c $DOWNLOADS_DIR/$(basename "$SDCARD_IMG").gz | sudo dd of=/dev/YOUR_SD_CARD bs=10M status=progress"
else
    # Flash directly to SD card
    log_info "Flashing SD card: $SD_CARD_DEVICE"
    log_info ""
    log_info "WARNING: This will erase all data on $SD_CARD_DEVICE"
    log_info "Make sure this is the correct device!"
    log_info ""
    read -p "Press Enter to continue, or Ctrl+C to cancel..."
    
    if [ "$USE_DOCKER" = true ]; then
        # On macOS, check if device exists
        if [ ! -e "$SD_CARD_DEVICE" ]; then
            log_error "SD card device not found: $SD_CARD_DEVICE"
            log_info "On macOS, SD cards typically appear as /dev/disk2, /dev/disk3, etc."
            log_info "Use 'diskutil list' to find your SD card"
            exit 1
        fi
        
        # Unmount the device first (macOS requirement)
        log_info "Unmounting SD card..."
        diskutil unmountDisk "$SD_CARD_DEVICE" 2>/dev/null || true
        
        # Get the raw device (rdisk on macOS) - faster for dd operations
        RAW_DEVICE="${SD_CARD_DEVICE/disk/rdisk}"
        
        if [ ! -e "$RAW_DEVICE" ]; then
            log_error "Raw device not found: $RAW_DEVICE"
            exit 1
        fi
        
        log_info "Using Docker for SD card flashing on macOS..."
        log_info "Device: $SD_CARD_DEVICE (raw: $RAW_DEVICE)"
        
        # On macOS, we need to use the raw device and pass it to Docker
        # Docker on macOS can access block devices with --device flag
        docker run --rm -it \
            --privileged \
            -v "$TMPDIR:/workspace" \
            --device "$RAW_DEVICE" \
            -w /workspace \
            ubuntu:22.04 bash -c "
            apt-get update -qq && \
            apt-get install -y -qq device-tree-compiler >/dev/null 2>&1 && \
            ./dosdcard.sh $(basename $RAW_DEVICE)
        "
    else
        # On Linux, flash directly
        if ! command -v dtc >/dev/null 2>&1; then
            log_error "device-tree-compiler (dtc) not found. Install it first."
            exit 1
        fi
        
        sudo ./dosdcard.sh "$SD_CARD_DEVICE"
    fi
    
    log_success "SD card flashed successfully!"
fi

