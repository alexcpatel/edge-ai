#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

APP="${1:-}"
DEVICE_HOST="${2:-edge-ai}"
DEVICE_USER="${3:-root}"

if [ -z "$APP" ]; then
    log_error "APP is required (e.g. app-deploy APP=animal-detector DEVICE_HOST=...)"
    exit 1
fi

APP_DIR="$REPO_ROOT/firmware/apps/$APP"
[ -d "$APP_DIR" ] || { log_error "App directory not found: $APP_DIR"; exit 1; }

check_device "$DEVICE_HOST" "$DEVICE_USER"

TARGET="${DEVICE_USER}@${DEVICE_HOST}"
REMOTE_TMP="/tmp/edge-apps"

log_info "Deploying app '$APP' to $TARGET..."

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$TARGET" "mkdir -p $REMOTE_TMP"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r "$APP_DIR" "$TARGET:$REMOTE_TMP/"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$TARGET" "
  set -euo pipefail
  APP='$APP'
  REMOTE_DIR='$REMOTE_TMP/$APP'
  mkdir -p /data/apps/\$APP /data/services
  cp -r \"\$REMOTE_DIR/app\" /data/apps/\$APP/ || true
  docker build -t edge/\$APP:latest \"\$REMOTE_DIR\"
  cp \"\$REMOTE_DIR/service.service\" /data/services/\$APP.service
  systemctl daemon-reload
  systemctl enable --now \$APP.service
"

log_info "App '$APP' deployed"


