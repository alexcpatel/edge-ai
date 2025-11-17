#!/bin/bash
# Clean Yocto build artifacts

set -e

source "$(dirname "$0")/../../infrastructure/scripts/lib/common.sh"

instance_id=$(get_instance_id)
ip=$(get_instance_ip "$instance_id")

log_info "Cleaning build..."

ssh_cmd "$ip" \
    "cd $YOCTO_DIR && \
     source poky/oe-init-build-env build && \
     bitbake -c cleanall $YOCTO_IMAGE || true"

log_success "Clean completed"

