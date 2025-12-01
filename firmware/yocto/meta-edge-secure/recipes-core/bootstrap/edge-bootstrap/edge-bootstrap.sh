#!/bin/bash
# Edge AI First Boot Bootstrap
# Runs once on first boot to provision device

set -euo pipefail

log() { echo "[edge-bootstrap] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
err() { log "ERROR: $*" >&2; }

PROVISION_MARKER="/data/.need_provisioning"
PROVISION_DONE="/data/.provisioned"
DATA_DIR="/data"
APPS_DIR="$DATA_DIR/apps"
SERVICES_DIR="$DATA_DIR/services"
CONFIG_DIR="$DATA_DIR/config"

# Ensure data directories exist
setup_data_partition() {
    log "Setting up data partition structure..."
    mkdir -p "$APPS_DIR" "$SERVICES_DIR" "$CONFIG_DIR"
    mkdir -p "$DATA_DIR/docker"  # For container storage
}

main() {
    log "Starting first-boot bootstrap..."

    if [ ! -f "$PROVISION_MARKER" ]; then
        log "Provision marker not found, skipping bootstrap"
        exit 0
    fi

    setup_data_partition

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

    # Step 3: Mark provisioning complete
    rm -f "$PROVISION_MARKER"
    date -Iseconds > "$PROVISION_DONE"

    log "Bootstrap complete!"

    # Trigger systemd to reload and pick up any new services
    systemctl daemon-reload
}

main "$@"

