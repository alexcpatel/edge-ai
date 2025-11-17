#!/bin/bash
# Build Yocto image

set -e

source "$(dirname "$0")/../../infrastructure/scripts/lib/common.sh"

instance_id=$(get_instance_id)
ip=$(get_instance_ip "$instance_id")

log_info "Starting Yocto build..."

ssh_cmd "$ip" -t \
    "cd $YOCTO_DIR && \
     source poky/oe-init-build-env build && \
     bitbake $YOCTO_IMAGE"

log_success "Build completed"

