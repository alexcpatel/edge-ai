#!/bin/bash
# Configure GPU and nvidia-container-runtime for Tegra
set -euo pipefail

log() { echo "[edge-gpu-setup] $*"; }

# Wake up GPU (Tegra suspends it by default)
GPU_POWER="/sys/devices/platform/17000000.gpu/power/control"
if [ -f "$GPU_POWER" ]; then
    echo on > "$GPU_POWER"
    log "GPU powered on"
    sleep 2
fi

# Fix NVIDIA device permissions for container access
# Without this, nvidia-container-cli fails with "Permission denied"
log "Setting NVIDIA device permissions..."
chmod 666 /dev/nvmap 2>/dev/null || true
chmod 666 /dev/nvhost* 2>/dev/null || true
chmod 666 /dev/nvsciipc 2>/dev/null || true
chmod -R 777 /dev/nvgpu 2>/dev/null || true

# Force nvidia-container-runtime to CSV mode (auto mode fails on Tegra)
NCR_CONFIG="/etc/nvidia-container-runtime/config.toml"
if [ -f "$NCR_CONFIG" ]; then
    if grep -q 'mode = "auto"' "$NCR_CONFIG"; then
        sed -i 's/mode = "auto"/mode = "csv"/' "$NCR_CONFIG"
        log "Set nvidia-container-runtime to CSV mode"
    fi
fi

# Ensure /etc/docker has nvidia runtime config
if [ -d /data/config/docker ] && [ -f /data/config/docker/daemon.json ]; then
    if [ ! -f /etc/docker/daemon.json ]; then
        mkdir -p /etc/docker
        mount --bind /data/config/docker /etc/docker 2>/dev/null || \
            cp /data/config/docker/daemon.json /etc/docker/
        log "Docker config ready"
    fi
fi

log "GPU setup complete"
