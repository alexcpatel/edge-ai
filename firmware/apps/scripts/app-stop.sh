#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

APP="${1:-}"
DEVICE_HOST="${2:-edge-ai}"
DEVICE_USER="${3:-root}"

if [ -z "$APP" ]; then
    log_error "APP is required (e.g. app-stop APP=animal-detector DEVICE_HOST=...)"
    exit 1
fi

check_device "$DEVICE_HOST" "$DEVICE_USER"
TARGET="${DEVICE_USER}@${DEVICE_HOST}"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$TARGET" "
  set -euo pipefail
  systemctl disable --now $APP.service 2>/dev/null || true
  rm -f /data/services/$APP.service
  systemctl daemon-reload
"

log_info "App '$APP' stopped and disabled"


