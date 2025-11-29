#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Push tegraflash archive from EC2 directly to controller
# This script runs on your laptop and orchestrates pushing the archive to the controller
# Usage: ./push-tegraflash.sh [controller_name]
#   Defaults to steamdeck (used for flash-usb operations)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Save paths before sourcing (which may change directories)
EC2_INSTANCE_CONNECT="$REPO_ROOT/build/remote/scripts/lib/ec2-instance-connect.sh"

# Determine which controller to push to
if [ $# -eq 0 ]; then
    # Default to steamdeck for flash operations
    export CONTROLLER_NAME="steamdeck"
else
    if [[ "$1" != "raspberrypi" ]] && [[ "$1" != "steamdeck" ]]; then
        echo "Error: Invalid controller name: $1" >&2
        echo "Valid controllers: raspberrypi, steamdeck" >&2
        exit 1
    fi
    export CONTROLLER_NAME="$1"
fi

source "$SCRIPT_DIR/lib/controller-common.sh"
source "$REPO_ROOT/build/remote/scripts/lib/common.sh"

get_controller_info "$CONTROLLER_NAME"

log_info "Pushing tegraflash archive from EC2 to $CONTROLLER_NAME controller..."

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
controller_cmd "$CONTROLLER_NAME" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/tegraflash"

# Stream directly from EC2 to controller via laptop (no local staging)
log_info "Streaming directly from EC2 to controller (via NordVPN Meshnet)..."

# Use rsync to stream from EC2 through laptop to controller
# This avoids staging the file locally on the laptop
source "$EC2_INSTANCE_CONNECT"
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

# Stream from EC2 to controller using scp through the laptop
# Stage temporarily on laptop, then transfer to controller to avoid pipe corruption
log_info "Downloading from EC2 to controller..."
TMP_ARCHIVE=$(mktemp)
trap "rm -f $TMP_ARCHIVE" EXIT

# Download from EC2 to local temp file
log_info "Downloading from EC2..."
scp -i "$temp_key" -o StrictHostKeyChecking=no \
    "${EC2_USER}@${ip}:${TEGRAFLASH_ARCHIVE}" \
    "$TMP_ARCHIVE"

# Verify local file is valid
if ! file "$TMP_ARCHIVE" | grep -q "gzip"; then
    log_error "Downloaded file from EC2 is not a valid gzip archive"
    file "$TMP_ARCHIVE" || true
    exit 1
fi

# Transfer to controller using rsync (preserves binary)
log_info "Transferring to controller..."
controller_rsync "$CONTROLLER_NAME" "$TMP_ARCHIVE" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}:$CURRENT_CONTROLLER_BASE_DIR/tegraflash/${ARCHIVE_NAME}"

# Verify the file was transferred correctly
log_info "Verifying archive on controller..."
if ! controller_cmd "$CONTROLLER_NAME" "file $CURRENT_CONTROLLER_BASE_DIR/tegraflash/${ARCHIVE_NAME} | grep -q 'gzip'"; then
    log_error "Archive transfer failed - file is not a valid gzip archive"
    controller_cmd "$CONTROLLER_NAME" "file $CURRENT_CONTROLLER_BASE_DIR/tegraflash/${ARCHIVE_NAME}" || true
    exit 1
fi

# Clean up temp key
rm -f "$temp_key"

log_success "Tegraflash archive pushed to $CONTROLLER_NAME controller: $CURRENT_CONTROLLER_BASE_DIR/tegraflash/$ARCHIVE_NAME"

