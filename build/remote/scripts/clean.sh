#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Clean Yocto build artifacts
# Usage: clean.sh [package-name|all]
#   no args: clean current image
#   package-name: clean specific package
#   all: clean all artifacts including tmp

source "$(dirname "$0")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

if [ $# -eq 0 ]; then
    log_info "Cleaning build artifacts..."
    yocto_cmd "$ip" "bitbake -c cleanall $YOCTO_IMAGE || true"
    log_success "Clean completed"
elif [ "$1" == "all" ]; then
    log_info "Cleaning all build artifacts..."
    yocto_cmd "$ip" "rm -rf tmp"
    log_success "Clean all completed"
else
    PACKAGE="$1"
    log_info "Cleaning package: $PACKAGE"
    yocto_cmd "$ip" "bitbake -c cleanall $PACKAGE || true"
    log_success "Package cleaned"
fi

