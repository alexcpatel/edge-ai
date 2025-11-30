#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLLER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$CONTROLLER_DIR/../../.." && pwd)"

source "$CONTROLLER_DIR/config/controller-config.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info() { echo -e "${YELLOW}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_error() { echo -e "${RED}$*${NC}"; }

validate_controller() {
    is_valid_controller "$1" || {
        log_error "Invalid controller: $1 (valid: $(list_controllers))"
        exit 1
    }
}

require_controller() {
    [ -z "${1:-}" ] && { log_error "Controller required: $(list_controllers)"; exit 1; }
    validate_controller "$1"
}

get_controller_info() {
    local name="$1"
    CURRENT_CONTROLLER_USER="$(get_controller_user "$name")"
    CURRENT_CONTROLLER_HOST="$(get_controller_host "$name")"
    CURRENT_CONTROLLER_BASE_DIR="/home/${CURRENT_CONTROLLER_USER}/edge-ai-controller"
}

check_controller_connection() {
    local name="$1"
    get_controller_info "$name"
    ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" "true" 2>/dev/null || {
        log_error "Cannot reach '$name' at ${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}"
        exit 1
    }
}

controller_ssh() {
    local name="$1"; shift
    get_controller_info "$name"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" "$@"
}

controller_rsync() {
    local name="$1"; shift
    get_controller_info "$name"
    rsync -e "ssh -o StrictHostKeyChecking=no" -avz --progress "$@"
}
