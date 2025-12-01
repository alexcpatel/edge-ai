#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

id=$(get_instance_id)
[ -z "$id" ] || [ "$id" == "None" ] && { log_error "Instance not found"; exit 1; }

state=$(get_instance_state "$id")
[ "$state" != "running" ] && { log_error "Instance is $state (must be running)"; exit 1; }

ip=$(get_instance_ip_or_exit)
KAS_CONFIG="${REMOTE_SOURCE_DIR}/firmware/yocto/config/kas.yml"
BUILD_DIR="${YOCTO_DIR}/build"

cleanup_bitbake() {
    log_info "Cleaning up BitBake..."
    ssh_cmd "$ip" "pkill -f 'bitbake' 2>/dev/null; rm -f $BUILD_DIR/bitbake.lock $BUILD_DIR/bitbake.sock" 2>/dev/null || true
    sleep 1
}

run_cleanall() {
    ssh_cmd "$ip" "cd $YOCTO_DIR && export PATH=\"\$HOME/.local/bin:\$PATH\" && kas shell $KAS_CONFIG -c 'bitbake -c cleanall $1'"
}

CLEAN_ALL=false CLEAN_PKG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --all) CLEAN_ALL=true; shift ;;
        --package) [ -z "${2:-}" ] && { log_error "--package requires a name"; exit 1; }; CLEAN_PKG="$2"; shift 2 ;;
        *) log_error "Unknown: $1"; exit 1 ;;
    esac
done

[ "$CLEAN_ALL" = false ] && [ -z "$CLEAN_PKG" ]

cleanup_bitbake

if [ "$CLEAN_ALL" = true ]; then
    log_info "Cleaning all artifacts..."
    ssh_cmd "$ip" "rm -rf $YOCTO_DIR/build/tmp $YOCTO_DIR/build/cache" 2>/dev/null || true
    log_success "All artifacts cleaned"
elif [ -n "$CLEAN_PKG" ]; then
    log_info "Cleaning package: $CLEAN_PKG"
    run_cleanall "$CLEAN_PKG"
    log_success "Package cleaned"
fi
