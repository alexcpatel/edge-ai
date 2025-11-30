#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Set up SSH key authentication to controllers
# This script runs on your laptop
# Usage: ./setup-ssh-keys.sh [controller_name]
#   If controller_name is not specified, sets up both raspberrypi and steamdeck

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/controller-common.sh"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Setting Up SSH Key Authentication${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Check if SSH key exists
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    log_info "SSH key not found. Generating new key..."
    ssh-keygen -t ed25519 -C "laptop-to-controller" -f "$SSH_KEY" -N ""
    log_success "SSH key generated: $SSH_KEY"
else
    log_success "SSH key found: $SSH_KEY"
fi

PUBLIC_KEY="$SSH_KEY.pub"
if [ ! -f "$PUBLIC_KEY" ]; then
    log_error "Public key not found: $PUBLIC_KEY"
    exit 1
fi

# Function to set up SSH keys for a specific controller
setup_controller_ssh() {
    local controller_name="$1"
    get_controller_info "$controller_name"

    log_info ""
    log_info "${BOLD}Setting up SSH keys for $controller_name${NC}"
    log_info "Hostname: ${CURRENT_CONTROLLER_HOSTNAME}"
    log_info "User: ${CURRENT_CONTROLLER_USER}"
    log_info ""

    # Copy key to controller (will prompt for password)
    log_step "Copying SSH public key to $controller_name..."
    log_info "You will be prompted for your password once..."

    ssh-copy-id -i "$PUBLIC_KEY" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}" || {
        log_info ""
        log_info "If ssh-copy-id failed, try manually:"
        log_info "  cat $PUBLIC_KEY | ssh ${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME} 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'"
        return 1
    }

    log_success "SSH key copied to $controller_name"

    # Test passwordless SSH
    log_step "Testing passwordless SSH connection to $controller_name..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}" "echo 'Passwordless SSH works!'" 2>/dev/null; then
        log_success "Passwordless SSH authentication is working for $controller_name!"
    else
        log_error "Passwordless SSH test failed for $controller_name"
        log_info "You may need to check:"
        log_info "  1. SSH key permissions: chmod 600 $SSH_KEY"
        log_info "  2. Remote .ssh directory permissions: ssh ${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME} 'chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'"
        return 1
    fi
}

# Determine which controllers to set up
if [ $# -eq 0 ]; then
    # Set up both controllers
    CONTROLLERS=("raspberrypi" "steamdeck")
else
    # Set up specified controller
    if [[ "$1" != "raspberrypi" ]] && [[ "$1" != "steamdeck" ]]; then
        log_error "Invalid controller name: $1"
        log_info "Valid controllers: raspberrypi, steamdeck"
        exit 1
    fi
    CONTROLLERS=("$1")
fi

# Set up SSH keys for each controller
FAILED=0
for controller in "${CONTROLLERS[@]}"; do
    if ! setup_controller_ssh "$controller"; then
        FAILED=1
    fi
done

if [ $FAILED -eq 1 ]; then
    log_error "SSH key setup failed for one or more controllers"
    exit 1
fi

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  SSH Key Setup Complete!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "You can now run controller commands without entering a password:"
log_info "  make controller-setup"
log_info "  make controller-update"
log_info ""

