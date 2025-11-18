#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Setup Yocto environment on EC2

source "$(dirname "$0")/lib/common.sh"
YOCTO_SCRIPTS_DIR="$(dirname "$0")/../../yocto/scripts"

ip=$(get_instance_ip_or_exit)

log_info "Setting up Yocto environment..."

# Run setup script with environment variables
ssh_cmd "$ip" \
    "YOCTO_BRANCH='$YOCTO_BRANCH' \
     YOCTO_MACHINE='$YOCTO_MACHINE' \
     YOCTO_DIR='$YOCTO_DIR' \
     SSTATE_DIR='$SSTATE_DIR' \
     DL_DIR='$DL_DIR' \
     bash -s" < "$YOCTO_SCRIPTS_DIR/setup-yocto.sh"

log_success "Yocto setup completed"
