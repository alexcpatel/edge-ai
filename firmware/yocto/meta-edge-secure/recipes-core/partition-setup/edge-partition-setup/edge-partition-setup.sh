#!/bin/bash
# Format /data partition on first boot
# Partition is created at flash time by flash-device.sh patching the layout
# This script formats it as ext4 if not already formatted

set -euo pipefail

DATA_PARTITION="/dev/nvme0n1p16"
DATA_MOUNT="/data"

log() { echo "[partition-setup] $*"; }

# Wait for partition to appear (may take a moment after boot)
for i in $(seq 1 30); do
    [ -b "$DATA_PARTITION" ] && break
    sleep 1
done

if [ ! -b "$DATA_PARTITION" ]; then
    log "ERROR: Data partition $DATA_PARTITION not found"
    log "Partition was not created during flash - check flash-device.sh"
    exit 1
fi

# Check if already formatted
if blkid "$DATA_PARTITION" | grep -q 'TYPE="ext4"'; then
    log "Data partition already formatted as ext4"
    exit 0
fi

log "Formatting $DATA_PARTITION as ext4..."
mkfs.ext4 -F -L data "$DATA_PARTITION"

# Mount temporarily to create initial structure
log "Creating initial directory structure..."
mount "$DATA_PARTITION" "$DATA_MOUNT"
mkdir -p "$DATA_MOUNT/apps"
mkdir -p "$DATA_MOUNT/services"
mkdir -p "$DATA_MOUNT/config"
mkdir -p "$DATA_MOUNT/docker"
mkdir -p "$DATA_MOUNT/log"
touch "$DATA_MOUNT/.need_provisioning"
umount "$DATA_MOUNT"

SIZE_GB=$(blockdev --getsize64 "$DATA_PARTITION" 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}' || echo "unknown")
log "Data partition ready (${SIZE_GB}GB)"

