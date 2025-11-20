#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Upload Yocto build source files to EC2 instance

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

log_info "Uploading Yocto build source files to EC2..."
ssh_cmd "$ip" "mkdir -p $REMOTE_SOURCE_DIR $YOCTO_DIR/config"

# Only upload what's needed for Yocto builds
rsync_cmd "$ip" -avz --progress \
    --include='layers/' \
    --include='layers/**' \
    --include='sources/' \
    --include='sources/**' \
    --include='build/' \
    --include='build/yocto/' \
    --include='build/yocto/**' \
    --exclude='*' \
    --exclude='.git' \
    "$REPO_ROOT/" \
    "${EC2_USER}@${ip}:${REMOTE_SOURCE_DIR}/"

# KAS will generate local.conf and bblayers.conf automatically, so no need to upload them

log_success "Upload completed"

