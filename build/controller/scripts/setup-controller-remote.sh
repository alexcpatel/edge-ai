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

# Test SSH access (allow password authentication during setup)
log_step "Testing SSH connection to controller..."
log_info "You may be prompted for a password..."
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}" "echo 'SSH connection successful'" 2>/dev/null; then
    log_error "Cannot connect to controller at ${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}"
    log_info ""
    log_info "Make sure:"
    log_info "  1. NordVPN Meshnet is enabled on both devices"
    log_info "  2. SSH is working: ssh ${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}"
    log_info "  3. CONTROLLER_HOSTNAME is set correctly in controller-config.sh"
    exit 1
fi

log_success "SSH connection verified"

# Copy setup script to controller
log_step "Copying setup script to controller..."
SETUP_SCRIPT="$SCRIPT_DIR/setup-controller.sh"
TMP_SCRIPT="/tmp/setup-controller-$$.sh"

# Use rsync directly (bypass check_controller_connection for setup phase)
rsync -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
    -avz --progress \
    "$SETUP_SCRIPT" \
    "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}:${TMP_SCRIPT}"

# Run setup script on controller
log_step "Running setup script on controller..."
log_info "This will install Docker and set up directories..."
log_info ""

# Run setup script (use SSH directly to allow password if needed)
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}" "bash $TMP_SCRIPT"

# Clean up
log_step "Cleaning up..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}" "rm -f $TMP_SCRIPT"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Remote Setup Complete!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "Next step: Deploy controller software"
log_info "  make controller-update"
log_info ""

