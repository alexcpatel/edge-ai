#!/bin/bash
# Download Yocto SDK from EC2 instance

set -e

source "$(dirname "$0")/../../infrastructure/scripts/lib/common.sh"

instance_id=$(get_instance_id)
if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
    log_error "Instance not found"
    exit 1
fi

ip=$(get_instance_ip "$instance_id")
if [ -z "$ip" ] || [ "$ip" == "None" ]; then
    log_error "Instance not running. Start it first or build an image."
    exit 1
fi

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

