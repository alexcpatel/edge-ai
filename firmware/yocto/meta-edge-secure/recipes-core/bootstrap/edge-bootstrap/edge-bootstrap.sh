#!/bin/bash
# Edge AI First Boot Bootstrap
# Runs on boot to provision device if not already provisioned

set -euo pipefail

log() { echo "[edge-bootstrap] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
err() { log "ERROR: $*" >&2; }

PROVISION_MARKER="/data/.need_provisioning"
PROVISION_DONE="/data/.provisioned"
DATA_DIR="/data"

# Ensure data directories exist (runs every boot, idempotent)
setup_data_partition() {
    log "Ensuring data partition structure..."
    mkdir -p "$DATA_DIR/apps"
    mkdir -p "$DATA_DIR/services"
    mkdir -p "$DATA_DIR/config"
    mkdir -p "$DATA_DIR/docker"
    mkdir -p "$DATA_DIR/log"
    mkdir -p "$DATA_DIR/sandbox"  # For unsigned dev containers

    # Copy container config from rootfs to data partition (idempotent)
    mkdir -p "$DATA_DIR/config/pki"
    mkdir -p "$DATA_DIR/config/ecr"
    if [ -f /etc/edge-ai/container-config/container-signing.pub ]; then
        cp -n /etc/edge-ai/container-config/container-signing.pub "$DATA_DIR/config/pki/" 2>/dev/null || true
    fi
    if [ -f /etc/edge-ai/container-config/ecr-url.txt ]; then
        cp -n /etc/edge-ai/container-config/ecr-url.txt "$DATA_DIR/config/ecr/" 2>/dev/null || true
    fi
}

main() {
    log "Starting bootstrap..."

    # Always ensure directory structure
    setup_data_partition

    # Check if already provisioned
    if [ -f "$PROVISION_DONE" ] && [ -s "$PROVISION_DONE" ]; then
        log "Device already provisioned ($(cat "$PROVISION_DONE")), skipping"
        exit 0
    fi

    log "Device not provisioned, starting provisioning..."

    # Step 1: AWS IoT Fleet Provisioning
    log "Running AWS IoT provisioning..."
    if /usr/bin/edge-provision.py; then
        log "AWS IoT provisioning complete"
    else
        err "AWS IoT provisioning failed"
        exit 1
    fi

    # Step 2: NordVPN Meshnet setup
    log "Setting up NordVPN meshnet..."
    if /usr/bin/edge-nordvpn.sh; then
        log "NordVPN meshnet setup complete"
    else
        # Non-fatal - device can still work without VPN
        err "NordVPN setup failed (continuing anyway)"
    fi

    # Mark provisioning complete and clean up
    rm -f "$PROVISION_MARKER"
    date '+%Y-%m-%dT%H:%M:%S%z' > "$PROVISION_DONE"

    log "Bootstrap complete!"

    # Trigger systemd to reload and pick up any new services
    systemctl daemon-reload
}

main "$@"
