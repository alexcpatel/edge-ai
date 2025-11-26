#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Common functions for Raspberry Pi controller operations

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

# Check if controller is reachable via Tailscale
check_controller_connection() {
    if ! ping -c 1 -W 2 "$CONTROLLER_HOSTNAME" >/dev/null 2>&1; then
        log_error "Cannot reach controller at $CONTROLLER_HOSTNAME"
        log_info "Make sure:"
        log_info "  1. Tailscale is running on both your laptop and Raspberry Pi"
        log_info "  2. Both devices are on the same Tailscale network"
        log_info "  3. CONTROLLER_HOSTNAME is set correctly in controller-config.sh"
        exit 1
    fi
}

# SSH to controller via Tailscale
controller_ssh() {
    check_controller_connection
    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}" "$@"
}

# Rsync to controller via Tailscale
controller_rsync() {
    check_controller_connection
    rsync -e "ssh -o StrictHostKeyChecking=no" \
        -avz --progress "$@"
}

# Execute command on controller
controller_cmd() {
    controller_ssh "$@"
}

