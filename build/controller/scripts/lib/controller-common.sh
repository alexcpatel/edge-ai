#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Common functions for controller operations
# Supports multiple controllers: raspberrypi and steamdeck

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/build/remote/config/aws-config.sh"
source "$REPO_ROOT/build/yocto/config/yocto-config.sh"
source "$REPO_ROOT/build/controller/config/controller-config.sh"
source "$REPO_ROOT/build/remote/scripts/lib/common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_error() { echo -e "${RED}$*${NC}"; }
log_step() { echo -e "${BLUE}${BOLD}→ $*${NC}"; }

# Get controller hostname and user for a specific controller
# Usage: get_controller_info <controller_name>
# Sets: CURRENT_CONTROLLER_HOSTNAME, CURRENT_CONTROLLER_USER, CURRENT_CONTROLLER_BASE_DIR
get_controller_info() {
    local controller_name="${1:-$CONTROLLER_NAME}"
    CURRENT_CONTROLLER_HOSTNAME="$(get_controller_hostname "$controller_name")"
    CURRENT_CONTROLLER_USER="$(get_controller_user "$controller_name")"
    CURRENT_CONTROLLER_BASE_DIR="/home/${CURRENT_CONTROLLER_USER}/edge-ai-controller"
}

# Check if controller is reachable via NordVPN Meshnet
# Uses SSH test instead of ping (more reliable with Meshnet)
# Usage: check_controller_connection [controller_name]
check_controller_connection() {
    local controller_name="${1:-$CONTROLLER_NAME}"
    get_controller_info "$controller_name"

    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}" "true" 2>/dev/null; then
        log_error "Cannot reach controller '$controller_name' at ${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}"
        log_info "Make sure:"
        log_info "  1. NordVPN Meshnet is enabled on both your laptop and the controller"
        log_info "  2. Both devices are connected to Meshnet (nordvpn meshnet peer list)"
        log_info "  3. Controller hostname is set correctly in controller-config.sh"
        log_info "  4. SSH works: ssh ${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}"
        exit 1
    fi
}

# SSH to controller via NordVPN Meshnet
# Usage: controller_ssh [controller_name] <command>
controller_ssh() {
    local controller_name="$CONTROLLER_NAME"
    # If first arg is a known controller name, use it
    if [[ "$1" == "raspberrypi" ]] || [[ "$1" == "steamdeck" ]]; then
        controller_name="$1"
        shift
    fi

    check_controller_connection "$controller_name"
    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}" "$@"
}

# Rsync to controller via NordVPN Meshnet
# Usage: controller_rsync [controller_name] <rsync_args>
controller_rsync() {
    local controller_name="$CONTROLLER_NAME"
    # If first arg is a known controller name, use it
    if [[ "$1" == "raspberrypi" ]] || [[ "$1" == "steamdeck" ]]; then
        controller_name="$1"
        shift
    fi

    check_controller_connection "$controller_name"
    rsync -e "ssh -o StrictHostKeyChecking=no" \
        -avz --progress "$@"
}

# Execute command on controller
# Usage: controller_cmd [controller_name] <command>
controller_cmd() {
    controller_ssh "$@"
}

