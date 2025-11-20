#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Download tegraflash archive from EC2 instance

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

# Artifacts directory on EC2
ARTIFACTS_DIR="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"

log_info "Looking for tegraflash archive on EC2..."
if ! ssh_cmd "$ip" "test -d $ARTIFACTS_DIR" 2>/dev/null; then
    log_error "Artifacts directory not found: $ARTIFACTS_DIR"
    log_error "Build an image first: make build-image"
    exit 1
fi

# Find tegraflash archive
TEGRAFLASH_TAR=$(ssh_cmd "$ip" "find $ARTIFACTS_DIR -maxdepth 1 -name '*.tegraflash.tar.gz' 2>/dev/null | head -1" || echo "")

if [ -z "$TEGRAFLASH_TAR" ]; then
    log_error "No tegraflash archive found. Build an image with IMAGE_FSTYPES=\"tegraflash\" first."
    exit 1
fi

ARCHIVE_NAME=$(basename "$TEGRAFLASH_TAR")
log_info "Found tegraflash archive: $ARCHIVE_NAME"

# Get Downloads folder path (works on macOS and Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    DOWNLOADS_DIR="$HOME/Downloads"
else
    DOWNLOADS_DIR="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
fi

# Create Downloads directory if it doesn't exist
mkdir -p "$DOWNLOADS_DIR"

# Download the archive
log_info "Downloading tegraflash archive to $DOWNLOADS_DIR..."
scp -i "$EC2_SSH_KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${EC2_USER}@${ip}:${TEGRAFLASH_TAR}" \
    "$DOWNLOADS_DIR/" || {
    log_error "Failed to download tegraflash archive"
    exit 1
}

log_success "Tegraflash archive downloaded to $DOWNLOADS_DIR/$ARCHIVE_NAME"

