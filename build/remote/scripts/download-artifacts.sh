#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Download Yocto build artifacts from EC2 instance

source "$(dirname "$0")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

# Artifacts directory on EC2
ARTIFACTS_DIR="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"

log_info "Checking for build artifacts on EC2..."
if ! ssh_cmd "$ip" "test -d $ARTIFACTS_DIR" 2>/dev/null; then
    log_error "Artifacts directory not found: $ARTIFACTS_DIR"
    log_error "Build an image first: make build-image"
    exit 1
fi

# List available artifacts
log_info "Available artifacts:"
ssh_cmd "$ip" "ls -lh $ARTIFACTS_DIR | grep -E '\.(wic|img|ext4|tar\.gz|dtb|bin)$' || echo 'No artifacts found'" || true

# Get destination and optional file from arguments
DEST_DIR="${1:-}"
ARTIFACT_FILE="${2:-}"

if [ -z "$DEST_DIR" ]; then
    log_error "Destination directory required"
    log_error "Usage: $0 <destination_directory> [artifact_file]"
    exit 1
fi

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

if [ -n "$ARTIFACT_FILE" ]; then
    # Download specific artifact
    log_info "Downloading $ARTIFACT_FILE to $DEST_DIR..."
    scp -i "$EC2_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        "${EC2_USER}@${ip}:${ARTIFACTS_DIR}/${ARTIFACT_FILE}" \
        "$DEST_DIR/" || {
        log_error "Failed to download $ARTIFACT_FILE"
        exit 1
    }
else
    # Download all artifacts
    log_info "Downloading all artifacts to $DEST_DIR..."
    rsync -avz --progress \
        -e "ssh -i $EC2_SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
        --include='*.wic' \
        --include='*.img' \
        --include='*.ext4' \
        --include='*.tar.gz' \
        --include='*.dtb' \
        --include='*.bin' \
        --include='*.wic.bmap' \
        --exclude='*' \
        "${EC2_USER}@${ip}:${ARTIFACTS_DIR}/" \
        "$DEST_DIR/" || {
        log_info "Some artifacts may not exist (this is normal)"
    }
fi

log_success "Artifacts downloaded to $DEST_DIR"
