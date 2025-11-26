#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Set up SSH key authentication to controller
# This script runs on your laptop

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

# Copy public key to controller
log_step "Copying SSH public key to controller..."
log_info "You will be prompted for your password once..."

PUBLIC_KEY="$SSH_KEY.pub"
if [ ! -f "$PUBLIC_KEY" ]; then
    log_error "Public key not found: $PUBLIC_KEY"
    exit 1
fi

# Copy key to controller (will prompt for password)
ssh-copy-id -i "$PUBLIC_KEY" "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}" || {
    log_info ""
    log_info "If ssh-copy-id failed, try manually:"
    log_info "  cat $PUBLIC_KEY | ssh ${CONTROLLER_USER}@${CONTROLLER_HOSTNAME} 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'"
    exit 1
}

log_success "SSH key copied to controller"

# Test passwordless SSH
log_step "Testing passwordless SSH connection..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}" "echo 'Passwordless SSH works!'" 2>/dev/null; then
    log_success "Passwordless SSH authentication is working!"
else
    log_error "Passwordless SSH test failed"
    log_info "You may need to check:"
    log_info "  1. SSH key permissions: chmod 600 $SSH_KEY"
    log_info "  2. Remote .ssh directory permissions: ssh ${CONTROLLER_USER}@${CONTROLLER_HOSTNAME} 'chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'"
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

