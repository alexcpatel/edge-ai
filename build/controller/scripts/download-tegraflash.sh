#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Download tegraflash archive from EC2 directly to Raspberry Pi controller
# This script runs on your laptop and orchestrates the download to the controller

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$SCRIPT_DIR/lib/controller-common.sh"
source "$REPO_ROOT/build/remote/scripts/lib/common.sh"

log_info "Downloading tegraflash archive from EC2 directly to Raspberry Pi controller..."

# Get EC2 instance IP
ip=$(get_instance_ip_or_exit)

# Find tegraflash archive on EC2
ARTIFACTS_DIR_REMOTE="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"

log_info "Looking for tegraflash archive on EC2..."
TEGRAFLASH_ARCHIVE=$(ssh_cmd "$ip" "find $ARTIFACTS_DIR_REMOTE -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | sort -r | head -1" || echo "")

if [ -z "$TEGRAFLASH_ARCHIVE" ]; then
    log_error "No tegraflash archive found on EC2."
    log_error "Build an image first: make build-image"
    exit 1
fi

ARCHIVE_NAME=$(basename "$TEGRAFLASH_ARCHIVE")
log_info "Found tegraflash archive: $ARCHIVE_NAME"

# Ensure controller directories exist
log_info "Setting up directories on controller..."
controller_cmd "mkdir -p $CONTROLLER_TEGRAFLASH_DIR"

# Stream directly from EC2 to controller via laptop (no local staging)
log_info "Streaming directly from EC2 to controller (via Tailscale)..."

# Use rsync to stream from EC2 through laptop to controller
# This avoids staging the file locally on the laptop
source "$(dirname "${BASH_SOURCE[0]}")/../remote/scripts/lib/ec2-instance-connect.sh"
instance_id=$(get_instance_id)
if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
    log_error "Instance not found"
    exit 1
fi

# Get temporary SSH key for EC2
temp_key=$(setup_temp_ssh_key "$instance_id")
if [ -z "$temp_key" ]; then
    log_error "Failed to setup SSH key for EC2"
    exit 1
fi

# Stream from EC2 to controller using rsync through the laptop
# rsync from EC2 (using temp key) piped to controller (using Tailscale)
log_info "Downloading and streaming to controller..."
rsync -e "ssh -i $temp_key -o StrictHostKeyChecking=no" \
    -avz --progress \
    "${EC2_USER}@${ip}:${TEGRAFLASH_ARCHIVE}" \
    - | controller_ssh "cat > ${CONTROLLER_TEGRAFLASH_DIR}/${ARCHIVE_NAME}"

# Clean up temp key
rm -f "$temp_key"

log_success "Tegraflash archive downloaded to controller: $CONTROLLER_TEGRAFLASH_DIR/$ARCHIVE_NAME"

