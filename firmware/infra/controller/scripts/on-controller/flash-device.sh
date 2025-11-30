#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash device script - runs on the controller
# This script is deployed to the controller and executed remotely

# This script runs on the controller (steamdeck for flash operations)
# Source config from the controller's base directory
CONTROLLER_BASE_DIR="${CONTROLLER_BASE_DIR:-/home/steamdeck/edge-ai-controller}"
if [ -f "$CONTROLLER_BASE_DIR/config/controller-config.sh" ]; then
    source "$CONTROLLER_BASE_DIR/config/controller-config.sh"
fi

ARCHIVE_PATH="$1"
FLASH_MODE="${2:-spi-only}"

if [ -z "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive path not provided" >&2
    exit 1
fi

# Validate flash mode
if [ "$FLASH_MODE" != "spi-only" ] && [ "$FLASH_MODE" != "full" ]; then
    echo "ERROR: Invalid flash mode: $FLASH_MODE (must be 'spi-only' or 'full')" >&2
    exit 1
fi

# Check if file exists
if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive file not found: $ARCHIVE_PATH" >&2
    echo "Looking in: $CONTROLLER_TEGRAFLASH_DIR" >&2
    ls -la "$CONTROLLER_TEGRAFLASH_DIR" >&2 || true
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

    if [ ! -f "./doflash.sh" ]; then
        echo "ERROR: doflash.sh not found in tegraflash archive" >&2
        exit 1
    fi

    # Mark what archive this was extracted from
    echo "$ARCHIVE_PATH" > "$EXTRACT_MARKER"
    chmod +x ./*.sh 2>/dev/null || true
    echo "Extraction complete"
else
    cd "$EXTRACT_DIR" || exit 1
fi

# Debug: Check architecture and USB devices
echo "=== Architecture Debug Info ==="
echo "Host architecture: $(uname -m)"
echo "Tegraflash binary info:"
file "$EXTRACT_DIR/tegrarcm_v2" 2>/dev/null || echo "tegrarcm_v2 not found"
ls -la "$EXTRACT_DIR/tegrarcm_v2" 2>/dev/null || true
echo "==============================="

# Check for NVIDIA USB device before running
echo "Checking for NVIDIA USB device..."
if ! lsusb | grep -i nvidia >/dev/null 2>&1; then
    echo "WARNING: No NVIDIA USB device detected. Make sure device is in recovery mode." >&2
    echo "Run 'lsusb | grep -i nvidia' to verify device is connected." >&2
else
    echo "NVIDIA USB device detected:"
    lsusb | grep -i nvidia
fi

# Run flashing natively (Ubuntu/steamdeck can run tegraflash tools directly)
echo "Running flash script natively..."
cd "$EXTRACT_DIR" || exit 1

# Build flash command based on mode
if [ "$FLASH_MODE" = "full" ]; then
    FLASH_CMD="./doflash.sh"
    echo "Flash mode: FULL (bootloader + rootfs)"
else
    FLASH_CMD="./doflash.sh --spi-only"
    echo "Flash mode: SPI-only (bootloader only)"
fi

# Check if we need sudo (typically required for USB device access)
if [ "$EUID" -ne 0 ]; then
    echo "Running with sudo (required for USB device access)..."
    sudo "$FLASH_CMD"
else
    $FLASH_CMD
fi

