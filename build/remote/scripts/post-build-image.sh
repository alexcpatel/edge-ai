#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Post-build script: Create SD card image from tegraflash archive
# This runs locally and executes commands on EC2 via SSH

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

# Artifacts directory on EC2
ARTIFACTS_DIR="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"
# Use a dedicated artifacts directory outside yocto output to avoid permission issues
# Path will be constructed in remote commands to ensure $HOME expands on remote
SDCARD_DIR_REMOTE="\$HOME/edge-ai-artifacts/sdcard"

log_info "Creating SD card image from tegraflash archive..."

# Find tegraflash archive - use ls with pattern matching as fallback if find fails
log_info "Searching for tegraflash archive in $ARTIFACTS_DIR..."
TEGRAFLASH_TAR=$(ssh_cmd "$ip" "find '$ARTIFACTS_DIR' -maxdepth 1 -name '*.tegraflash.tar.gz' -type f 2>/dev/null | head -1" || echo "")

# If find didn't work, try ls with pattern
if [ -z "$TEGRAFLASH_TAR" ]; then
    log_info "Trying alternative search method..."
    TEGRAFLASH_TAR=$(ssh_cmd "$ip" "ls -1 '$ARTIFACTS_DIR'/*.tegraflash.tar.gz 2>/dev/null | head -1" || echo "")
fi

# If still not found, list what's actually there for debugging
if [ -z "$TEGRAFLASH_TAR" ]; then
    log_error "No tegraflash archive found. Build may have failed or used different image type."
    log_info "Files in $ARTIFACTS_DIR:"
    ssh_cmd "$ip" "ls -la '$ARTIFACTS_DIR'/*.tar.gz 2>/dev/null || echo 'No .tar.gz files found'" || true
    exit 1
fi

ARCHIVE_NAME=$(basename "$TEGRAFLASH_TAR")
log_info "Found tegraflash archive: $ARCHIVE_NAME"

# Create temporary directory for extraction on EC2
log_info "Creating temporary directory for extraction..."
REMOTE_TMPDIR=$(ssh_cmd "$ip" "mktemp -d")

# Cleanup function to remove temp directory on EC2
cleanup_remote_tmpdir() {
    log_info "Cleaning up temporary directory..."
    ssh_cmd "$ip" "rm -rf '$REMOTE_TMPDIR'" 2>/dev/null || true
}
trap cleanup_remote_tmpdir EXIT

log_info "Extracting tegraflash archive..."
ssh_cmd "$ip" "cd '$REMOTE_TMPDIR' && tar -xzf '$TEGRAFLASH_TAR'"

# Check if dosdcard.sh exists
if ! ssh_cmd "$ip" "test -f '$REMOTE_TMPDIR/dosdcard.sh'"; then
    log_error "dosdcard.sh not found in tegraflash archive"
    exit 1
fi

# Check and install device-tree-compiler if needed
log_info "Checking for device-tree-compiler (dtc)..."
if ! ssh_cmd "$ip" "command -v dtc >/dev/null 2>&1"; then
    log_info "Installing device-tree-compiler package..."
    ssh_cmd "$ip" "sudo apt-get update -y && sudo apt-get install -y device-tree-compiler" || {
        log_error "Failed to install device-tree-compiler"
        exit 1
    }
else
    log_info "device-tree-compiler already installed"
fi

# Make scripts executable and create SD card image
log_info "Creating SD card image..."
ssh_cmd "$ip" "cd '$REMOTE_TMPDIR' && chmod +x ./*.sh 2>/dev/null || true && ./dosdcard.sh"

# Find the created SD card image
REMOTE_IMG=$(ssh_cmd "$ip" "find '$REMOTE_TMPDIR' -maxdepth 1 -name '*.img' -type f | head -1")

if [ -z "$REMOTE_IMG" ]; then
    log_error "SD card image not found after running dosdcard.sh"
    exit 1
fi

IMG_NAME=$(basename "$REMOTE_IMG")
log_success "SD card image created: $IMG_NAME"

# Create artifacts output directory and move image there
log_info "Moving SD card image to artifacts directory..."
ssh_cmd "$ip" "mkdir -p $SDCARD_DIR_REMOTE"
ssh_cmd "$ip" "mv '$REMOTE_IMG' $SDCARD_DIR_REMOTE/"

# Compress the SD card image
log_info "Compressing SD card image..."
ssh_cmd "$ip" "cd $SDCARD_DIR_REMOTE && gzip -f '$IMG_NAME'"

COMPRESSED_IMG="${IMG_NAME}.gz"
log_success "SD card image compressed: $COMPRESSED_IMG"
log_info "SD card image available at: $SDCARD_DIR_REMOTE/$COMPRESSED_IMG"

