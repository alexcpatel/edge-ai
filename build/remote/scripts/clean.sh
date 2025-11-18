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
KAS_CONFIG="${REMOTE_SOURCE_DIR}/build/yocto/config/kas.yml"

# Helper function to clean up bitbake processes and lock files
cleanup_bitbake() {
    local ip="$1"
    log_info "Cleaning up BitBake processes and lock files..."

    # Kill any running bitbake server processes
    ssh_cmd "$ip" "pkill -f 'bitbake.*server' || true"
    ssh_cmd "$ip" "pkill -f 'bitbake.*-m' || true"

    # Remove bitbake lock files
    ssh_cmd "$ip" "find $YOCTO_DIR -name 'bitbake.lock' -type f -delete 2>/dev/null || true"
    ssh_cmd "$ip" "find $YOCTO_DIR -name 'bitbake.sock' -type f -delete 2>/dev/null || true"

    # Wait a moment for processes to terminate
    sleep 1
}

# Always clean up bitbake processes and lock files first
cleanup_bitbake "$ip"

if [ $# -eq 0 ]; then
    log_info "Cleaning build artifacts..."
    # Use kas shell to get into the environment, then run bitbake cleanall
    ssh_cmd "$ip" "cd $YOCTO_DIR && export PATH=\"\$HOME/.local/bin:\$PATH\" && kas shell $KAS_CONFIG -c 'bitbake -c cleanall $YOCTO_IMAGE || true'"
    log_success "Clean completed"
elif [ "$1" == "all" ]; then
    log_info "Cleaning all build artifacts..."
    # Remove tmp directory (kas manages the build directory structure)
    ssh_cmd "$ip" "cd $YOCTO_DIR && find . -type d -name 'tmp' -exec rm -rf {} + 2>/dev/null || true"
    log_success "Clean all completed"
else
    PACKAGE="$1"
    log_info "Cleaning package: $PACKAGE"
    # Use kas shell to get into the environment, then run bitbake cleanall
    ssh_cmd "$ip" "cd $YOCTO_DIR && export PATH=\"\$HOME/.local/bin:\$PATH\" && kas shell $KAS_CONFIG -c 'bitbake -c cleanall $PACKAGE || true'"
    log_success "Package cleaned"
fi

