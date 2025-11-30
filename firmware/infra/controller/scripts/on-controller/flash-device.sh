#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

CONTROLLER_BASE_DIR="${CONTROLLER_BASE_DIR:-$HOME/edge-ai-controller}"
ARCHIVE_PATH="$1"
FLASH_MODE="${2:-spi-only}"
LOG_FILE="${LOG_FILE:-/tmp/usb-flash.log}"

[ -z "$ARCHIVE_PATH" ] && { echo "Usage: $0 <archive> [spi-only|full]"; exit 1; }
[ ! -f "$ARCHIVE_PATH" ] && { echo "Archive not found: $ARCHIVE_PATH"; exit 1; }
file "$ARCHIVE_PATH" | grep -q "gzip" || { echo "Not a gzip archive"; exit 1; }
[[ "$FLASH_MODE" == "spi-only" || "$FLASH_MODE" == "full" ]] || { echo "Invalid mode: $FLASH_MODE"; exit 1; }

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
    [ -f "$EXTRACT_DIR/doflash.sh" ] || { echo "doflash.sh not found"; exit 1; }
    chmod +x "$EXTRACT_DIR"/*.sh 2>/dev/null || true
    touch "$MARKER"
fi

cd "$EXTRACT_DIR"

[ -f "./doflash.sh" ] || { echo "doflash.sh not found in $EXTRACT_DIR"; exit 1; }

lsusb | grep -qi nvidia && echo "NVIDIA device detected" \
    || echo "WARNING: No NVIDIA USB device. Ensure device is in recovery mode."

if [ "$FLASH_MODE" = "full" ]; then
    CMD="./doflash.sh"
else
    CMD="./doflash.sh"
    ARGS="--spi-only"
fi

echo "Flashing ($FLASH_MODE)..."
if [ "$EUID" -ne 0 ]; then
    sudo "$CMD" "${ARGS:-}" 2>&1 | tee "$LOG_FILE"
    FLASH_EXIT="${PIPESTATUS[0]}"
else
    "$CMD" "${ARGS:-}" 2>&1 | tee "$LOG_FILE"
    FLASH_EXIT="${PIPESTATUS[0]}"
fi

exit "$FLASH_EXIT"
