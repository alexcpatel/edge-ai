#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Remote setup script - runs setup-controller.sh on the Raspberry Pi via SSH
# This script runs on your laptop and sets up the controller remotely
# Usage: ./setup-controller-remote.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/controller-common.sh"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Setting up Raspberry Pi Controller Remotely${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Check connection first
log_step "Testing connection to controller..."
if ! ping -c 1 -W 2 "$CONTROLLER_HOSTNAME" >/dev/null 2>&1; then
    log_error "Cannot reach controller at $CONTROLLER_HOSTNAME"
    log_info "Make sure:"
    log_info "  1. NordVPN Meshnet is enabled on both devices"
    log_info "  2. Both devices are connected to Meshnet (nordvpn meshnet peer list)"
    log_info "  3. CONTROLLER_HOSTNAME is set correctly in controller-config.sh"
    exit 1
fi

# Test SSH access
log_step "Testing SSH access..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}" "echo 'SSH connection successful'" 2>/dev/null; then
    log_error "Cannot SSH to controller without password"
    log_info ""
    log_info "Set up SSH key authentication:"
    log_info "  1. Generate key (if needed): ssh-keygen -t ed25519"
    log_info "  2. Copy key: ssh-copy-id ${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}"
    log_info "  3. Or run manually: cat ~/.ssh/id_ed25519.pub | ssh ${CONTROLLER_USER}@${CONTROLLER_HOSTNAME} 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'"
    exit 1
fi

log_success "Connection verified"

# Copy setup script to controller
log_step "Copying setup script to controller..."
SETUP_SCRIPT="$SCRIPT_DIR/setup-controller.sh"
TMP_SCRIPT="/tmp/setup-controller-$$.sh"

controller_rsync "$SETUP_SCRIPT" "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}:${TMP_SCRIPT}"

# Run setup script on controller
log_step "Running setup script on controller..."
log_info "This will install Docker and set up directories..."
log_info ""

controller_ssh "bash $TMP_SCRIPT"

# Clean up
log_step "Cleaning up..."
controller_cmd "rm -f $TMP_SCRIPT"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Remote Setup Complete!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "Next step: Deploy controller software"
log_info "  make controller-update"
log_info ""

