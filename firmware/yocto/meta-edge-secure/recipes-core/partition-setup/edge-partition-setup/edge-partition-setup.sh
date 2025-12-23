#!/bin/bash
# Format /data partition and set up directory structure on first boot
set -euo pipefail

DATA_PARTITION="/dev/nvme0n1p16"
DATA_MOUNT="/data"

log() { echo "[partition-setup] $*"; }

# Wait for partition to appear
for i in $(seq 1 30); do
    [ -b "$DATA_PARTITION" ] && break
    sleep 1
done

if [ ! -b "$DATA_PARTITION" ]; then
    log "ERROR: Data partition $DATA_PARTITION not found"
    exit 1
fi

# Format if needed
if ! blkid "$DATA_PARTITION" | grep -q 'TYPE="ext4"'; then
    log "Formatting $DATA_PARTITION as ext4..."
    mkfs.ext4 -F -L data "$DATA_PARTITION"
fi

# Temporarily mount to set up directories
mkdir -p "$DATA_MOUNT"
mount "$DATA_PARTITION" "$DATA_MOUNT" 2>/dev/null || true

# Create directory structure
mkdir -p "$DATA_MOUNT/docker"
mkdir -p "$DATA_MOUNT/config/docker"
mkdir -p "$DATA_MOUNT/config/NetworkManager"
mkdir -p "$DATA_MOUNT/log"
mkdir -p "$DATA_MOUNT/sandbox"

# Create docker config with nvidia runtime
if [ ! -f "$DATA_MOUNT/config/docker/daemon.json" ]; then
    cat > "$DATA_MOUNT/config/docker/daemon.json" << 'EOF'
{
    "data-root": "/data/docker",
    "storage-driver": "vfs",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
    log "Created docker config"
fi

# Mark done
touch "$DATA_MOUNT/.partition-setup-done"

umount "$DATA_MOUNT" 2>/dev/null || true

log "Data partition ready"
