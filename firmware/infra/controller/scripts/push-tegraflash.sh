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

ARCHIVE_NAME=$(basename "$ARCHIVE")
log_info "Found: $ARCHIVE_NAME"

controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/tegraflash"

REMOTE_ARCHIVE="$CURRENT_CONTROLLER_BASE_DIR/tegraflash/$ARCHIVE_NAME"
REMOTE_EXISTS=$(controller_ssh "$CONTROLLER" "[ -f '$REMOTE_ARCHIVE' ] && echo 'yes' || echo 'no'" | tr -d '\r\n')

if [ "$REMOTE_EXISTS" = "yes" ]; then
    log_info "Checking if archive needs update..."
    REMOTE_CHECKSUM=$(controller_ssh "$CONTROLLER" "sha256sum '$REMOTE_ARCHIVE' 2>/dev/null | cut -d' ' -f1" | tr -d '\r\n')

    TMP_FILE=$(mktemp)
    trap "rm -f $TMP_FILE" EXIT

    log_info "Downloading from EC2 to verify..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${EC2_USER}@${ip}:${ARCHIVE}" "$TMP_FILE"

    file "$TMP_FILE" | grep -q "gzip" || { log_error "Downloaded file is not a valid gzip archive"; exit 1; }

    LOCAL_CHECKSUM=$(sha256sum "$TMP_FILE" | cut -d' ' -f1)

    if [ "$REMOTE_CHECKSUM" = "$LOCAL_CHECKSUM" ]; then
        log_success "Archive already exists with matching checksum, skipping upload"
        rm -f "$TMP_FILE"
    else
        log_info "Archive differs, uploading..."
        controller_rsync "$CONTROLLER" "$TMP_FILE" \
            "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$REMOTE_ARCHIVE"
        rm -f "$TMP_FILE"
    fi

else
    TMP_FILE=$(mktemp)
    trap "rm -f $TMP_FILE" EXIT

    log_info "Downloading from EC2..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${EC2_USER}@${ip}:${ARCHIVE}" "$TMP_FILE"

    file "$TMP_FILE" | grep -q "gzip" || { log_error "Downloaded file is not a valid gzip archive"; exit 1; }

    log_info "Uploading to controller..."
    controller_rsync "$CONTROLLER" "$TMP_FILE" \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$REMOTE_ARCHIVE"
    rm -f "$TMP_FILE"
fi

controller_ssh "$CONTROLLER" "file $REMOTE_ARCHIVE | grep -q 'gzip'" || {
    log_error "Transfer failed - archive corrupted"; exit 1
}

log_info "Cleaning up old archives (keeping latest 3)..."
controller_ssh "$CONTROLLER" "cd $CURRENT_CONTROLLER_BASE_DIR/tegraflash && \
    ls -t *.tegraflash.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do [ -n \"\$f\" ] && rm -f \"\$f\"; done"

log_info "Cleaning up extracted directories for non-existent archives..."
controller_ssh "$CONTROLLER" "if [ -d '$CURRENT_CONTROLLER_BASE_DIR/tegraflash-extracted' ]; then
    for dir in $CURRENT_CONTROLLER_BASE_DIR/tegraflash-extracted/*; do
        [ -d \"\$dir\" ] || continue
        ARCHIVE_NAME=\$(basename \"\$dir\")
        [ -f \"$CURRENT_CONTROLLER_BASE_DIR/tegraflash/\${ARCHIVE_NAME}.tegraflash.tar.gz\" ] || rm -rf \"\$dir\"
    done
fi"

log_success "Tegraflash pushed to $CONTROLLER"
