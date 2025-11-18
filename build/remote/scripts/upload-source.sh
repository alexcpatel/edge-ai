#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Upload Yocto build source files to EC2 instance

source "$(dirname "$0")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

log_info "Uploading Yocto build source files to EC2..."
ssh_cmd "$ip" "mkdir -p $REMOTE_SOURCE_DIR $YOCTO_DIR/config"

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
    -e "ssh -i $EC2_SSH_KEY_PATH -o StrictHostKeyChecking=no" \
    "$REPO_ROOT/" \
    "${EC2_USER}@${ip}:${REMOTE_SOURCE_DIR}/"

# Copy config files directly to where they'll be used
YOCTO_CONFIG_DIR="$(dirname "$0")/../../yocto/config"
rsync -avz -e "ssh -i $EC2_SSH_KEY_PATH -o StrictHostKeyChecking=no" \
    "$YOCTO_CONFIG_DIR/local.conf" \
    "$YOCTO_CONFIG_DIR/bblayers.conf" \
    "${EC2_USER}@${ip}:${YOCTO_DIR}/config/"

log_success "Upload completed"

