#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Download SD card image from EC2 instance

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

# Artifacts directory on EC2 (outside yocto output to avoid permission issues)
# Path will be constructed in remote commands to ensure $HOME expands on remote
SDCARD_DIR_REMOTE="\$HOME/edge-ai-artifacts/sdcard"

log_info "Looking for SD card image on EC2..."
if ! ssh_cmd "$ip" "test -d $SDCARD_DIR_REMOTE" 2>/dev/null; then
    log_error "SD card directory not found: $SDCARD_DIR_REMOTE"
    log_error "Build an image first: make build-image"
    log_error "Then create SD card image: make build-post-image"
    exit 1
fi

# Find compressed SD card image
SDCARD_IMG=$(ssh_cmd "$ip" "find $SDCARD_DIR_REMOTE -maxdepth 1 -name '*.sdcard.gz' -type f 2>/dev/null | head -1" || echo "")

if [ -z "$SDCARD_IMG" ]; then
    log_error "No SD card image (.sdcard.gz) found."
    exit 1
fi

IMG_NAME=$(basename "$SDCARD_IMG")
log_info "Found SD card image: $IMG_NAME"

# Get Downloads folder path (works on macOS and Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    DOWNLOADS_DIR="$HOME/Downloads"
else
    DOWNLOADS_DIR="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
fi

# Create Downloads directory if it doesn't exist
mkdir -p "$DOWNLOADS_DIR"

# Download the image
log_info "Downloading SD card image to $DOWNLOADS_DIR..."
rsync_cmd "$ip" -avz --progress "${EC2_USER}@${ip}:${SDCARD_IMG}" "$DOWNLOADS_DIR/"

log_success "SD card image downloaded to $DOWNLOADS_DIR/$IMG_NAME"

