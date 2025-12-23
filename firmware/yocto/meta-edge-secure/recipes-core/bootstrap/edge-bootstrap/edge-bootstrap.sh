#!/bin/bash
# Edge AI First Boot Bootstrap - AWS IoT Fleet Provisioning
set -euo pipefail

log() { echo "[edge-bootstrap] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
err() { log "ERROR: $*" >&2; }

PROVISION_DONE="/data/.provisioned"

# Check if already provisioned
if [ -f "$PROVISION_DONE" ]; then
    log "Already provisioned ($(cat "$PROVISION_DONE"))"
    exit 0
fi

log "Starting AWS IoT provisioning..."

if /usr/bin/edge-provision.py; then
    date '+%Y-%m-%dT%H:%M:%S%z' > "$PROVISION_DONE"
    log "Provisioning complete"
    systemctl daemon-reload
else
    err "Provisioning failed"
    exit 1
fi
