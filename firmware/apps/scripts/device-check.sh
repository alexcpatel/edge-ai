#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DEVICE_HOST="${1:-edge-ai}"
DEVICE_USER="${2:-root}"

check_device "$DEVICE_HOST" "$DEVICE_USER"
log_info "Device ${DEVICE_USER}@${DEVICE_HOST} is reachable"


