#!/bin/bash
# Configure GPU and nvidia-container-runtime for Tegra
set -euo pipefail

log() { echo "[edge-gpu-setup] $*"; }

# Wake up GPU (Tegra suspends it by default, causing "Permission denied" errors)
GPU_POWER="/sys/devices/platform/17000000.gpu/power/control"
if [ -f "$GPU_POWER" ]; then
    echo on > "$GPU_POWER"
    log "GPU powered on"
    # Wait for device nodes to appear
    sleep 2
fi

# Force nvidia-container-runtime to CSV mode (auto mode fails on Tegra)
NCR_CONFIG="/run/nvidia-container-runtime/config.toml"
if [ -f "$NCR_CONFIG" ]; then
    if grep -q 'mode = "auto"' "$NCR_CONFIG"; then
        sed -i 's/mode = "auto"/mode = "csv"/' "$NCR_CONFIG"
        log "Set nvidia-container-runtime to CSV mode"
    fi
fi

# Ensure /etc/docker has our config with nvidia runtime
if [ -d /data/config/docker ] && [ -f /data/config/docker/daemon.json ]; then
    if [ ! -f /etc/docker/daemon.json ]; then
        mkdir -p /etc/docker
        mount --bind /data/config/docker /etc/docker 2>/dev/null || \
            cp /data/config/docker/daemon.json /etc/docker/
        log "Docker config ready"
    fi
fi

log "GPU setup complete"
