#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash SD card device script - runs on the controller
# This script is deployed to the controller and executed remotely

# Source config from the controller's base directory
CONTROLLER_BASE_DIR="${CONTROLLER_BASE_DIR:-/home/steamdeck/edge-ai-controller}"
if [ -f "$CONTROLLER_BASE_DIR/config/controller-config.sh" ]; then
    source "$CONTROLLER_BASE_DIR/config/controller-config.sh"
fi

ARCHIVE_PATH="$1"
SD_CARD_DEVICE="${2:-}"

if [ -z "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive path not provided" >&2
    exit 1
fi

# Check if file exists
if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive file not found: $ARCHIVE_PATH" >&2
    echo "Looking in: $CONTROLLER_BASE_DIR/tegraflash" >&2
    ls -la "$CONTROLLER_BASE_DIR/tegraflash" >&2 || true
    exit 1
fi

# Verify it's actually a gzip file
if ! file "$ARCHIVE_PATH" | grep -q "gzip"; then
    echo "ERROR: File does not appear to be a gzip archive: $ARCHIVE_PATH" >&2
    file "$ARCHIVE_PATH" >&2
    exit 1
fi

# Extract tegraflash archive to persistent directory for debugging
ARCHIVE_NAME=$(basename "$ARCHIVE_PATH" .tegraflash.tar.gz)
EXTRACT_DIR="$CONTROLLER_BASE_DIR/tegraflash-extracted/$ARCHIVE_NAME"
EXTRACT_MARKER="$EXTRACT_DIR/.extracted-from"
NEEDS_EXTRACT=true

# Check if already extracted and archive hasn't changed
if [ -d "$EXTRACT_DIR" ] && [ -f "$EXTRACT_MARKER" ]; then
    MARKED_ARCHIVE=$(cat "$EXTRACT_MARKER" 2>/dev/null || echo "")
    if [ "$MARKED_ARCHIVE" = "$ARCHIVE_PATH" ]; then
        # Check if archive file still exists and hasn't been modified
        if [ -f "$ARCHIVE_PATH" ]; then
            ARCHIVE_MTIME=$(stat -c %Y "$ARCHIVE_PATH" 2>/dev/null || stat -f %m "$ARCHIVE_PATH" 2>/dev/null || echo "0")
            EXTRACT_MTIME=$(stat -c %Y "$EXTRACT_MARKER" 2>/dev/null || stat -f %m "$EXTRACT_MARKER" 2>/dev/null || echo "0")
            if [ "$EXTRACT_MTIME" -ge "$ARCHIVE_MTIME" ]; then
                echo "Archive already extracted, skipping extraction..."
                NEEDS_EXTRACT=false
            fi
        fi
    fi
fi

if [ "$NEEDS_EXTRACT" = true ]; then
    echo "Extracting archive to: $EXTRACT_DIR"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    cd "$EXTRACT_DIR" || exit 1

    tar -xzf "$ARCHIVE_PATH"

    if [ ! -f "./dosdcard.sh" ]; then
        echo "ERROR: dosdcard.sh not found in tegraflash archive" >&2
        exit 1
    fi

    # Mark what archive this was extracted from
    echo "$ARCHIVE_PATH" > "$EXTRACT_MARKER"
    chmod +x ./*.sh 2>/dev/null || true
    echo "Extraction complete"
else
    cd "$EXTRACT_DIR" || exit 1
fi

# If SD card device not provided, list available devices
if [ -z "$SD_CARD_DEVICE" ]; then
    echo ""
    echo "=== Available block devices ==="
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "^(NAME|sd|mmc|nvme)" || true
    echo ""
    echo "Please specify the SD card device (e.g., /dev/sdb, /dev/mmcblk0):"
    read -p "Device: " SD_CARD_DEVICE
    echo ""
fi

# Verify device exists
if [ ! -b "$SD_CARD_DEVICE" ]; then
    echo "ERROR: Block device not found: $SD_CARD_DEVICE" >&2
    echo "Available devices:" >&2
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "^(NAME|sd|mmc|nvme)" || true
    exit 1
fi

# Show device info for confirmation
echo "Device information:"
lsblk "$SD_CARD_DEVICE" || true
echo ""
echo "WARNING: This will erase all data on $SD_CARD_DEVICE"
read -p "Press Enter to continue, or Ctrl+C to cancel..."

# Unmount the device if mounted
echo "Unmounting device..."
sudo umount "${SD_CARD_DEVICE}"* 2>/dev/null || true

# Run dosdcard.sh
echo ""
echo "=== Starting SD card flash ==="
echo "Device: $SD_CARD_DEVICE"
echo "This may take several minutes. Please be patient..."
echo ""

# Check if we need sudo (typically required for block device access)
if [ "$EUID" -ne 0 ]; then
    echo "Running with sudo (required for block device access)..."
    sudo ./dosdcard.sh "$SD_CARD_DEVICE"
else
    ./dosdcard.sh "$SD_CARD_DEVICE"
fi

echo ""
echo "=== SD card flash complete ==="

