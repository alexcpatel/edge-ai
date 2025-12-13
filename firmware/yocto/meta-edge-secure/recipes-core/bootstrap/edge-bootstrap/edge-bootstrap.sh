#!/bin/bash
# Edge AI First Boot Bootstrap
# Runs on boot to provision device if not already provisioned

set -euo pipefail

log() { echo "[edge-bootstrap] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
err() { log "ERROR: $*" >&2; }

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
}

main() {
    log "Starting bootstrap..."

    # Always ensure directory structure
    setup_data_partition

    # Check if already provisioned
    if [ -f "$PROVISION_DONE" ]; then
        log "Device already provisioned ($(cat "$PROVISION_DONE")), skipping"
        exit 0
    fi

    log "Device not provisioned, starting provisioning..."

    # Step 1: AWS IoT Fleet Provisioning
    log "Running AWS IoT provisioning..."
    if /usr/bin/edge-provision.sh; then
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

    # Mark provisioning complete
    date -Iseconds > "$PROVISION_DONE"

    log "Bootstrap complete!"

    # Trigger systemd to reload and pick up any new services
    systemctl daemon-reload
}

main "$@"
