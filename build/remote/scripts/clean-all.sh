#!/bin/bash
# Clean all build artifacts including tmp

set -e

source "$(dirname "$0")/../../infrastructure/scripts/lib/common.sh"

instance_id=$(get_instance_id)
ip=$(get_instance_ip "$instance_id")

log_info "Cleaning all build artifacts..."

ssh_cmd "$ip" \
    "cd $YOCTO_DIR && \
     source poky/oe-init-build-env build && \
     rm -rf tmp"

log_success "Clean all completed"

