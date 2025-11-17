#!/bin/bash
# Sync repository to EC2 instance

set -e

source "$(dirname "$0")/lib/common.sh"

instance_id=$(get_instance_id)
ip=$(get_instance_ip "$instance_id")

log_info "Syncing repository to EC2..."
ssh_cmd "$ip" "mkdir -p $REMOTE_SOURCE_DIR"

rsync -avz --progress \
    --exclude='.git' \
    --exclude='build/infrastructure/config' \
    --exclude='*.wic' --exclude='*.img' --exclude='*.ext4' \
    -e "ssh -i $EC2_SSH_KEY_PATH -o StrictHostKeyChecking=no" \
    "$REPO_ROOT/" \
    "${EC2_USER}@${ip}:${REMOTE_SOURCE_DIR}/"

log_success "Sync completed"

