#!/bin/bash
# Setup Yocto environment on EC2

set -e

source "$(dirname "$0")/../../infrastructure/scripts/lib/common.sh"
YOCTO_SCRIPTS_DIR="$(dirname "$0")/../../yocto/scripts"

instance_id=$(get_instance_id)
ip=$(get_instance_ip "$instance_id")

log_info "Setting up Yocto environment..."

ssh_cmd "$ip" \
    "YOCTO_BRANCH='$YOCTO_BRANCH' \
     YOCTO_MACHINE='$YOCTO_MACHINE' \
     YOCTO_DIR='$YOCTO_DIR' \
     SSTATE_DIR='$SSTATE_DIR' \
     DL_DIR='$DL_DIR' \
     bash -s" < "$YOCTO_SCRIPTS_DIR/remote-setup-yocto.sh"

log_success "Yocto setup completed"
