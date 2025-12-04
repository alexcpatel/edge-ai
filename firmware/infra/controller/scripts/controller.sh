#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

show_status() {
    require_controller "${1:-}"
    local name="$1"
    get_controller_info "$name"

    echo "Controller: $name"
    echo "Host: ${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}"

    if ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" "true" 2>/dev/null; then
        echo "Status: reachable"
    else
        echo "Status: unreachable"
    fi
}

run_setup() {
    require_controller "${1:-}"
    local name="$1"
    get_controller_info "$name"

    log_info "Setting up $name..."

    local setup_dir="$SCRIPT_DIR/on-controller"
    [ ! -f "$setup_dir/setup.sh" ] && { log_error "Setup script not found"; exit 1; }

    local remote_setup_dir="/tmp/edge-setup-$$"
    controller_ssh "$name" "mkdir -p $remote_setup_dir"
    rsync -e "ssh -o StrictHostKeyChecking=no" -az \
        "$setup_dir/" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:${remote_setup_dir}/"
    controller_ssh "$name" "chmod +x $remote_setup_dir/*.sh && bash $remote_setup_dir/setup.sh && rm -rf $remote_setup_dir"

    log_success "Setup complete"
}

deploy_scripts() {
    require_controller "${1:-}"
    local name="$1"
    get_controller_info "$name"

    log_info "Deploying scripts to $name..."

    controller_ssh "$name" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/{scripts/on-controller,config}"

    controller_rsync "$name" \
        --exclude='*.sh~' --exclude='*.swp' --exclude='.DS_Store' \
        "$SCRIPT_DIR/" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$CURRENT_CONTROLLER_BASE_DIR/scripts/"

    controller_rsync "$name" \
        --exclude='*.sh~' --exclude='*.swp' --exclude='.DS_Store' \
        "$CONTROLLER_DIR/config/" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$CURRENT_CONTROLLER_BASE_DIR/config/"

    controller_ssh "$name" "chmod +x $CURRENT_CONTROLLER_BASE_DIR/scripts/*.sh $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/*.sh 2>/dev/null || true"

    log_success "Scripts deployed"
}

setup_ssh_keys() {
    require_controller "${1:-}"
    local name="$1"
    get_controller_info "$name"

    local ssh_key="$HOME/.ssh/id_ed25519"
    [ ! -f "$ssh_key" ] && {
        log_info "Generating SSH key..."
        ssh-keygen -t ed25519 -C "laptop-to-controller" -f "$ssh_key" -N ""
    }

    log_info "Setting up SSH keys for $name..."
    ssh-copy-id -i "${ssh_key}.pub" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" || {
        log_error "Failed for $name"; exit 1
    }
    log_success "SSH key copied to $name"
}

ssh_to_controller() {
    require_controller "${1:-}"
    local name="$1"; shift
    get_controller_info "$name"
    check_controller_connection "$name"
    [ $# -eq 0 ] && ssh -o StrictHostKeyChecking=no "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" \
        || controller_ssh "$name" "$@"
}

list_all() {
    for name in "${CONTROLLERS[@]}"; do
        get_controller_info "$name"
        printf "%-15s %s@%s\n" "$name" "$CURRENT_CONTROLLER_USER" "$CURRENT_CONTROLLER_HOST"
    done
}

check_usb_device() {
    require_controller "${1:-}"
    local name="$1"
    get_controller_info "$name"
    check_controller_connection "$name"

    if controller_ssh "$name" "lsusb | grep -qi nvidia" 2>/dev/null; then
        echo "detected"
    else
        echo "not_detected"
    fi
}

case "${1:-}" in
    status) show_status "${2:-}" ;;
    setup) run_setup "${2:-}" ;;
    deploy) deploy_scripts "${2:-}" ;;
    ssh-keys) setup_ssh_keys "${2:-}" ;;
    ssh) shift; ssh_to_controller "$@" ;;
    list) list_all ;;
    usb-device) check_usb_device "${2:-}" ;;
    *) echo "Usage: $0 [list|status|setup|deploy|ssh-keys|ssh|usb-device] [controller]"; exit 1 ;;
esac
