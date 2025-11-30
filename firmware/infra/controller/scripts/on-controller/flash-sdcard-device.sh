#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

CONTROLLER_BASE_DIR="${CONTROLLER_BASE_DIR:-$HOME/edge-ai-controller}"
ARCHIVE_PATH="$1"
SD_DEVICE="${2:-}"

[ -z "$ARCHIVE_PATH" ] && { echo "Usage: $0 <archive> [device]"; exit 1; }
[ ! -f "$ARCHIVE_PATH" ] && { echo "Archive not found: $ARCHIVE_PATH"; exit 1; }
file "$ARCHIVE_PATH" | grep -q "gzip" || { echo "Not a gzip archive"; exit 1; }

ARCHIVE_NAME=$(basename "$ARCHIVE_PATH" .tegraflash.tar.gz)
EXTRACT_DIR="$CONTROLLER_BASE_DIR/tegraflash-extracted/$ARCHIVE_NAME"
MARKER="$EXTRACT_DIR/.extracted"

if [ -f "$MARKER" ] && [ "$MARKER" -nt "$ARCHIVE_PATH" ]; then
    echo "Using cached extraction"
else
    echo "Extracting to $EXTRACT_DIR..."
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
    [ -f "$EXTRACT_DIR/dosdcard.sh" ] || { echo "dosdcard.sh not found"; exit 1; }
    chmod +x "$EXTRACT_DIR"/*.sh 2>/dev/null || true
    touch "$MARKER"
fi

cd "$EXTRACT_DIR"

if [ -z "$SD_DEVICE" ]; then
    echo "Available devices:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "^(NAME|sd|mmc|nvme)" || true
    read -p "Device (e.g. /dev/sdb): " SD_DEVICE
fi

[ -b "$SD_DEVICE" ] || { echo "Device not found: $SD_DEVICE"; exit 1; }

echo "Target: $SD_DEVICE"
lsblk "$SD_DEVICE" || true
echo "WARNING: This will erase all data on $SD_DEVICE"
read -p "Press Enter to continue, Ctrl+C to cancel..."

sudo umount "${SD_DEVICE}"* 2>/dev/null || true

echo "Flashing SD card..."
[ "$EUID" -ne 0 ] && sudo ./dosdcard.sh "$SD_DEVICE" || ./dosdcard.sh "$SD_DEVICE"

echo "SD card flash complete"
