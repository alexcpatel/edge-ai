#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

CONTROLLER_BASE_DIR="${CONTROLLER_BASE_DIR:-$HOME/edge-ai-controller}"
ARCHIVE_PATH="$1"
SD_DEVICE="${2:-}"
LOG_FILE="${LOG_FILE:-/tmp/sdcard-flash.log}"

exec > >(tee -a "$LOG_FILE") 2>&1

[ -z "$ARCHIVE_PATH" ] && { echo "Usage: $0 <archive> [device]"; exit 1; }
[ ! -f "$ARCHIVE_PATH" ] && { echo "Archive not found: $ARCHIVE_PATH"; exit 1; }
file "$ARCHIVE_PATH" | grep -q "gzip" || { echo "Not a gzip archive"; exit 1; }

ARCHIVE_NAME=$(basename "$ARCHIVE_PATH" .tegraflash.tar.gz)
EXTRACT_DIR="$CONTROLLER_BASE_DIR/tegraflash-extracted/$ARCHIVE_NAME"
MARKER="$EXTRACT_DIR/.extracted"

ARCHIVE_CHECKSUM=$(sha256sum "$ARCHIVE_PATH" | cut -d' ' -f1)
NEEDS_EXTRACT=true

if [ -f "$MARKER" ] && [ -f "$EXTRACT_DIR/dosdcard.sh" ]; then
    CACHED_CHECKSUM=$(cat "$MARKER" 2>/dev/null || echo "")
    if [ "$CACHED_CHECKSUM" = "$ARCHIVE_CHECKSUM" ]; then
        echo "Using cached extraction"
        NEEDS_EXTRACT=false
    fi
fi

if [ "$NEEDS_EXTRACT" = true ]; then
    echo "Extracting to $EXTRACT_DIR..."
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
    [ -f "$EXTRACT_DIR/dosdcard.sh" ] || { echo "dosdcard.sh not found"; exit 1; }
    chmod +x "$EXTRACT_DIR"/*.sh 2>/dev/null || true
    echo "$ARCHIVE_CHECKSUM" > "$MARKER"
fi

cd "$EXTRACT_DIR"

[ -z "$SD_DEVICE" ] && { echo "Error: Device is required"; exit 1; }

if [ "$SD_DEVICE" = "${SD_DEVICE#/dev/}" ]; then
    SD_DEVICE="/dev/$SD_DEVICE"
fi

[ -b "$SD_DEVICE" ] || { echo "Device not found: $SD_DEVICE"; exit 1; }

echo "Target: $SD_DEVICE"
lsblk "$SD_DEVICE" || true
echo "WARNING: This will erase all data on $SD_DEVICE"
echo "Proceeding with flash..."

sudo umount "${SD_DEVICE}"* 2>/dev/null || true

echo "Flashing SD card..."
FLASH_EXIT=0
if [ "$EUID" -ne 0 ]; then
    yes | sudo ./dosdcard.sh "$SD_DEVICE" 2>&1 | tee -a "$LOG_FILE"
    FLASH_EXIT="${PIPESTATUS[0]}"
else
    yes | ./dosdcard.sh "$SD_DEVICE" 2>&1 | tee -a "$LOG_FILE"
    FLASH_EXIT="${PIPESTATUS[0]}"
fi

if [ "$FLASH_EXIT" -eq 0 ]; then
    echo "SD card flash complete"
else
    echo "SD card flash failed with exit code $FLASH_EXIT"
fi

exit "$FLASH_EXIT"
