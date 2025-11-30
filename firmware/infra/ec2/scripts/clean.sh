#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Clean Yocto build artifacts
# Usage: clean.sh [--all|--package PACKAGE|--image]
#   --all: Remove all build artifacts (tmp, cache, etc.)
#   --package PACKAGE: Clean specific package
#   --image: Clean current image (default if no args)

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# Check if instance is running before attempting cleanup
instance_id=$(get_instance_id)
if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
    log_error "Instance '$EC2_INSTANCE_NAME' not found"
    exit 1
fi

instance_state=$(get_instance_state "$instance_id")
if [ "$instance_state" != "running" ]; then
    log_error "Instance is $instance_state (not running)"
    log_error "Instance must be running to perform cleanup operations"
    exit 1
fi

ip=$(get_instance_ip_or_exit)
KAS_CONFIG="${REMOTE_SOURCE_DIR}/build/yocto/config/kas.yml"
BUILD_DIR="${YOCTO_DIR}/build"

# Helper function to clean up bitbake processes and lock files
cleanup_bitbake() {
    local ip="$1"
    log_info "Cleaning up BitBake processes and lock files..."

    # Run all cleanup commands in a single SSH connection
    # Commands may fail (processes/files may not exist), so we ignore errors
    set +e
    ssh_cmd "$ip" "
        pkill -f 'bitbake.*server' 2>/dev/null;
        pkill -f 'bitbake.*-m' 2>/dev/null;
        rm -f $BUILD_DIR/bitbake.lock $BUILD_DIR/bitbake.sock 2>/dev/null
    "
    set -e

    # Wait a moment for processes to terminate
    sleep 1
}

# Helper function to run bitbake cleanall command via kas shell
run_bitbake_cleanall() {
    local ip="$1"
    local target="$2"
    ssh_cmd "$ip" "cd $YOCTO_DIR && export PATH=\"\$HOME/.local/bin:\$PATH\" && kas shell $KAS_CONFIG -c 'bitbake -c cleanall $target'"
}

# Clean all build artifacts (tmp and cache)
clean_all_artifacts() {
    local ip="$1"
    log_info "Cleaning all build artifacts..."
    set +e
    ssh_cmd "$ip" "cd $YOCTO_DIR && rm -rf build/tmp build/cache 2>/dev/null"
    set -e
    log_success "All build artifacts cleaned"
}

# Clean a specific package
clean_package() {
    local ip="$1"
    local package="$2"
    log_info "Cleaning package: $package"
    run_bitbake_cleanall "$ip" "$package"
    log_success "Package $package cleaned"
}

# Clean the current image
clean_image() {
    local ip="$1"
    log_info "Cleaning image: $YOCTO_IMAGE"
    run_bitbake_cleanall "$ip" "$YOCTO_IMAGE"
    log_success "Image $YOCTO_IMAGE cleaned"
}

# Parse arguments
CLEAN_ALL=false
CLEAN_PACKAGE=""
CLEAN_IMAGE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            CLEAN_ALL=true
            shift
            ;;
        --package)
            if [ -z "${2:-}" ]; then
                log_error "Error: --package requires a package name"
                exit 1
            fi
            CLEAN_PACKAGE="$2"
            shift 2
            ;;
        --image)
            CLEAN_IMAGE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            log_info "Usage: clean.sh [--all|--package PACKAGE|--image]"
            exit 1
            ;;
    esac
done

# Default to cleaning image if no options specified
if [ "$CLEAN_ALL" = "false" ] && [ -z "$CLEAN_PACKAGE" ] && [ "$CLEAN_IMAGE" = "false" ]; then
    CLEAN_IMAGE=true
fi

# Always clean up bitbake processes and lock files first
cleanup_bitbake "$ip"

# Execute clean operations
if [ "$CLEAN_ALL" = "true" ]; then
    clean_all_artifacts "$ip"
elif [ -n "$CLEAN_PACKAGE" ]; then
    clean_package "$ip" "$CLEAN_PACKAGE"
elif [ "$CLEAN_IMAGE" = "true" ]; then
    clean_image "$ip"
fi

