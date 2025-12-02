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
ARCHIVE=$(ssh_cmd "$ip" "ls -t $ARTIFACTS_DIR/*.tegraflash.tar.gz 2>/dev/null | head -1" || echo "")

[ -z "$ARCHIVE" ] && { log_error "No tegraflash archive on EC2. Build first: make build"; exit 1; }

ARCHIVE_NAME=$(basename "$ARCHIVE")
log_info "Found: $ARCHIVE_NAME"

controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/tegraflash"

REMOTE_ARCHIVE="$CURRENT_CONTROLLER_BASE_DIR/tegraflash/$ARCHIVE_NAME"

EC2_CHECKSUM=$(ssh_cmd "$ip" "md5sum '$ARCHIVE' | cut -d' ' -f1")
CONTROLLER_CHECKSUM=$(controller_ssh "$CONTROLLER" "md5sum '$REMOTE_ARCHIVE' 2>/dev/null | cut -d' ' -f1" || echo "")

if [ "$EC2_CHECKSUM" = "$CONTROLLER_CHECKSUM" ]; then
    log_success "Archive unchanged (checksum match), skipping upload"
else
    TMP_FILE=$(mktemp)
    trap "rm -f $TMP_FILE" EXIT

    log_info "Downloading from EC2..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${EC2_USER}@${ip}:${ARCHIVE}" "$TMP_FILE"

    file "$TMP_FILE" | grep -q "gzip" || { log_error "Not a valid gzip archive"; exit 1; }

    log_info "Uploading to controller..."
    controller_rsync "$CONTROLLER" "$TMP_FILE" \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$REMOTE_ARCHIVE"
fi

log_info "Cleaning up old archives (keeping latest 3)..."
controller_ssh "$CONTROLLER" "cd $CURRENT_CONTROLLER_BASE_DIR/tegraflash && \
    ls -t *.tegraflash.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do rm -f \"\$f\"; done"

log_info "Cleaning up stale extracted directories..."
controller_ssh "$CONTROLLER" "for dir in $CURRENT_CONTROLLER_BASE_DIR/tegraflash-extracted/*/; do
    [ -d \"\$dir\" ] || continue
    name=\$(basename \"\$dir\")
    [ -f \"$CURRENT_CONTROLLER_BASE_DIR/tegraflash/\${name}.tegraflash.tar.gz\" ] || sudo rm -rf \"\$dir\"
done"

log_success "Tegraflash pushed to $CONTROLLER"
