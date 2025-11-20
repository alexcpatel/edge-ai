#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Download Yocto SDK from EC2 instance

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

log_info "Finding SDK on EC2..."
sdk_path=$(ssh_cmd "$ip" "find $YOCTO_DIR/build/tmp/deploy/sdk -name '*.sh' -type f 2>/dev/null | head -1" || echo "")

if [ -z "$sdk_path" ]; then
    log_error "SDK not found. Build an image first: make build-image"
    exit 1
fi

sdk_name=$(basename "$sdk_path" .sh)
local_sdk_dir="$REPO_ROOT/sdk/$sdk_name"

if [ -d "$local_sdk_dir" ]; then
    log_info "SDK already exists locally at $local_sdk_dir"
    exit 0
fi

log_info "Downloading SDK..."
mkdir -p "$REPO_ROOT/sdk"
scp -i "$EC2_SSH_KEY_PATH" "${EC2_USER}@${ip}:${sdk_path}" "$REPO_ROOT/sdk/"
scp -i "$EC2_SSH_KEY_PATH" "${EC2_USER}@${ip}:${sdk_path%.sh}.tar.bz2" "$REPO_ROOT/sdk/" 2>/dev/null || true

log_success "SDK downloaded to $REPO_ROOT/sdk/$sdk_name"
log_info "Extract and source: cd sdk && tar xf $sdk_name.tar.bz2 && source $sdk_name/environment-setup-aarch64-poky-linux"

