#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

CONTROLLER_BASE_DIR="${CONTROLLER_BASE_DIR:-$HOME/edge-ai-controller}"
ARCHIVE_PATH="$1"
FLASH_MODE="${2:-bootloader}"
LOG_FILE="${LOG_FILE:-/tmp/usb-flash.log}"

# Size of rootfs partition (8GB), remainder becomes /data
ROOTFS_SIZE_BYTES=8589934592

# Clear log file at start of new flash
> "$LOG_FILE"
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

# Patch partition layout to add /data partition (rootfs mode only)
if [ "$FLASH_MODE" = "rootfs" ]; then
    LAYOUT_FILE="external-flash.xml.in"
    if [ -f "$LAYOUT_FILE" ]; then
        echo "Patching partition layout to add /data partition..."

        # Create DATA partition XML snippet (fills remaining space)
        DATA_PARTITION='        <partition name="DATA" id="16" type="data">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> 0xFFFFFFFFFFFFFFFF </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 0x808 </allocation_attribute>
            <align_boundary> 16384 </align_boundary>
            <percent_reserved> 0 </percent_reserved>
            <description> Writable data partition for /data mount </description>
        </partition>'

        # Backup original
        cp "$LAYOUT_FILE" "${LAYOUT_FILE}.orig"

        # 1. Change APP partition size to fixed value (remove fill-to-end)
        # 2. Change allocation_attribute from 0x808 to 0x8 (remove fill-to-end flag)
        # 3. Insert DATA partition before secondary_gpt

        python3 - "$LAYOUT_FILE" "$ROOTFS_SIZE_BYTES" "$DATA_PARTITION" << 'PYSCRIPT'
import sys
import re

layout_file = sys.argv[1]
rootfs_size = sys.argv[2]
data_partition = sys.argv[3]

with open(layout_file, 'r') as f:
    content = f.read()

# Find and modify APP partition
app_pattern = r'(<partition name="APP"[^>]*>.*?)(allocation_attribute>[^<]*</allocation_attribute>)(.*?)(size>[^<]*</size>)(.*?</partition>)'
def replace_app(m):
    prefix = m.group(1)
    alloc = 'allocation_attribute> 0x8 </allocation_attribute>'  # Remove fill-to-end flag
    middle = m.group(3)
    size = f'size> {rootfs_size} </size>'  # Fixed 8GB
    suffix = m.group(5)
    return prefix + alloc + middle + size + suffix

content = re.sub(app_pattern, replace_app, content, flags=re.DOTALL)

# Insert DATA partition before secondary_gpt
secondary_gpt_pattern = r'(\s*)(<partition name="secondary_gpt")'
content = re.sub(secondary_gpt_pattern, r'\1' + data_partition.replace('\n', r'\n\1') + r'\n\1\2', content)

with open(layout_file, 'w') as f:
    f.write(content)

print("Partition layout patched successfully")
PYSCRIPT

        echo "APP partition: ${ROOTFS_SIZE_BYTES} bytes (8GB)"
        echo "DATA partition: remaining space (fill-to-end)"
    else
        echo "WARNING: $LAYOUT_FILE not found, skipping partition patch"
    fi
fi

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
