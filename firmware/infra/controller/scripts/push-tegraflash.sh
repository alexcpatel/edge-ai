#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$REPO_ROOT/firmware/infra/ec2/scripts/lib/common.sh"

CONTROLLER="${1:-steamdeck}"
require_controller "$CONTROLLER"
get_controller_info "$CONTROLLER"

log_info "Pushing tegraflash from EC2 to $CONTROLLER..."

ip=$(get_instance_ip_or_exit)

ARTIFACTS_DIR="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"
ARCHIVE=$(ssh_cmd "$ip" "find $ARTIFACTS_DIR -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | sort -r | head -1" || echo "")

[ -z "$ARCHIVE" ] && { log_error "No tegraflash archive on EC2. Build first: make build"; exit 1; }

log_info "Found: $(basename "$ARCHIVE")"

controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/tegraflash"

TMP_FILE=$(mktemp)
trap "rm -f $TMP_FILE" EXIT

log_info "Downloading from EC2..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${EC2_USER}@${ip}:${ARCHIVE}" "$TMP_FILE"

file "$TMP_FILE" | grep -q "gzip" || { log_error "Downloaded file is not a valid gzip archive"; exit 1; }

log_info "Uploading to controller..."
controller_rsync "$CONTROLLER" "$TMP_FILE" \
    "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$CURRENT_CONTROLLER_BASE_DIR/tegraflash/$(basename "$ARCHIVE")"

controller_ssh "$CONTROLLER" "file $CURRENT_CONTROLLER_BASE_DIR/tegraflash/$(basename "$ARCHIVE") | grep -q 'gzip'" || {
    log_error "Transfer failed - archive corrupted"; exit 1
}

log_success "Tegraflash pushed to $CONTROLLER"
