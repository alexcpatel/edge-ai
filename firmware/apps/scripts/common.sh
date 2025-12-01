#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

log_info()  { echo "[apps] $*"; }
log_error() { echo "[apps] ERROR: $*" >&2; }

check_device() {
    local host="$1"
    local user="${2:-root}"

    if [ -z "$host" ]; then
        log_error "DEVICE_HOST is required"
        exit 1
    fi

    local target="${user}@${host}"
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$target" "echo ok" >/dev/null 2>&1; then
        log_error "Unable to reach ${target}"
        exit 1
    fi
}


