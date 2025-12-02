#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

CONTROLLER_BASE_DIR="${CONTROLLER_BASE_DIR:-$HOME/edge-ai-controller}"
ARCHIVE_PATH="$1"
FLASH_MODE="${2:-bootloader}"
LOG_FILE="${LOG_FILE:-/tmp/usb-flash.log}"

exec > >(tee -a "$LOG_FILE") 2>&1

[ -z "$ARCHIVE_PATH" ] && { echo "Usage: $0 <archive> [bootloader|rootfs]"; exit 1; }
[ ! -f "$ARCHIVE_PATH" ] && { echo "Archive not found: $ARCHIVE_PATH"; exit 1; }
file "$ARCHIVE_PATH" | grep -q "gzip" || { echo "Not a gzip archive"; exit 1; }
[[ "$FLASH_MODE" == "bootloader" || "$FLASH_MODE" == "rootfs" ]] || { echo "Invalid mode: $FLASH_MODE"; exit 1; }

ARCHIVE_NAME=$(basename "$ARCHIVE_PATH" .tegraflash.tar.gz)
EXTRACT_DIR="$CONTROLLER_BASE_DIR/tegraflash-extracted/$ARCHIVE_NAME"

REQUIRED_SCRIPT=$( [ "$FLASH_MODE" = "rootfs" ] && echo "initrd-flash" || echo "doflash.sh" )

echo "Extracting to $EXTRACT_DIR..."
sudo rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
[ -f "$EXTRACT_DIR/$REQUIRED_SCRIPT" ] || { echo "$REQUIRED_SCRIPT not found"; exit 1; }
chmod +x "$EXTRACT_DIR"/*.sh 2>/dev/null || true
[ "$FLASH_MODE" = "rootfs" ] && chmod +x "$EXTRACT_DIR/initrd-flash" 2>/dev/null || true

cd "$EXTRACT_DIR"

[ -f "./$REQUIRED_SCRIPT" ] || { echo "$REQUIRED_SCRIPT not found in $EXTRACT_DIR"; exit 1; }

lsusb | grep -qi nvidia && echo "NVIDIA device detected" \
    || echo "WARNING: No NVIDIA USB device. Ensure device is in recovery mode."

if [ "$FLASH_MODE" = "rootfs" ]; then
    CMD="./initrd-flash"
    ARGS="--skip-bootloader"
else
    CMD="./doflash.sh"
    ARGS="--spi-only"
fi

echo "Flashing ($FLASH_MODE)..."
FLASH_EXIT=0
if [ "$EUID" -ne 0 ]; then
    sudo "$CMD" "${ARGS:-}" 2>&1
    FLASH_EXIT="$?"
else
    "$CMD" "${ARGS:-}" 2>&1
    FLASH_EXIT="$?"
fi

if [ "$FLASH_EXIT" -eq 0 ]; then
    echo "USB flash complete"
else
    echo "USB flash failed with exit code $FLASH_EXIT"
fi

exit "$FLASH_EXIT"
