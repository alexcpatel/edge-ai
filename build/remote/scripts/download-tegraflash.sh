#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Download tegraflash archive from EC2 instance

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/build/remote/config/aws-config.sh"
source "$REPO_ROOT/build/yocto/config/yocto-config.sh"
source "$REPO_ROOT/build/remote/scripts/lib/common.sh"

ip=$(get_instance_ip_or_exit)

# Find tegraflash archive on EC2
ARTIFACTS_DIR_REMOTE="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"

log_info "Looking for tegraflash archive on EC2..."
TEGRAFLASH_ARCHIVE=$(ssh_cmd "$ip" "find $ARTIFACTS_DIR_REMOTE -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | head -1" || echo "")

if [ -z "$TEGRAFLASH_ARCHIVE" ]; then
    log_error "No tegraflash archive found."
    log_error "Build an image first: make build-image"
    exit 1
fi

ARCHIVE_NAME=$(basename "$TEGRAFLASH_ARCHIVE")
log_info "Found tegraflash archive: $ARCHIVE_NAME"

# Local directory for tegraflash archives
LOCAL_TEGRAFLASH_DIR="$REPO_ROOT/build/local/tegraflash"
mkdir -p "$LOCAL_TEGRAFLASH_DIR"

# Download the archive
log_info "Downloading tegraflash archive..."
rsync_cmd "$ip" -avz --progress "${EC2_USER}@${ip}:${TEGRAFLASH_ARCHIVE}" "$LOCAL_TEGRAFLASH_DIR/"

log_success "Tegraflash archive downloaded to $LOCAL_TEGRAFLASH_DIR/$ARCHIVE_NAME"

