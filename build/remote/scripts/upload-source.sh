#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Upload Yocto build source files to EC2 instance

source "$(dirname "$0")/lib/common.sh"

ip=$(get_instance_ip_or_exit)
instance_id=$(get_instance_id)

log_info "Uploading Yocto build source files to EC2..."
ssh_cmd "$ip" "mkdir -p $REMOTE_SOURCE_DIR $YOCTO_DIR/config"

# Use EC2 Instance Connect for rsync
source "$(dirname "$0")/lib/ec2-instance-connect.sh"
temp_key=$(setup_temp_ssh_key "$instance_id")
if [ $? -ne 0 ] || [ -z "$temp_key" ]; then
    log_error "Failed to send SSH public key via EC2 Instance Connect"
    exit 1
fi

_cleanup_key() {
    cleanup_temp_ssh_key "$temp_key"
}
trap _cleanup_key EXIT

# Only upload what's needed for Yocto builds
rsync -avz --progress \
    --include='layers/' \
    --include='layers/**' \
    --include='sources/' \
    --include='sources/**' \
    --include='build/' \
    --include='build/yocto/' \
    --include='build/yocto/**' \
    --exclude='*' \
    --exclude='.git' \
    -e "ssh -i $temp_key -o StrictHostKeyChecking=no" \
    "$REPO_ROOT/" \
    "${EC2_USER}@${ip}:${REMOTE_SOURCE_DIR}/"

cleanup_temp_ssh_key "$temp_key"
trap - EXIT

# KAS will generate local.conf and bblayers.conf automatically, so no need to upload them

log_success "Upload completed"

