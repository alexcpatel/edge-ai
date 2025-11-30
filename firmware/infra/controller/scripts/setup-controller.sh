#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Remote setup script - runs setup-controller.sh on a controller via SSH
# This script runs on your laptop and sets up the controller remotely
# Usage: ./setup-controller-remote.sh [controller_name]
#   If controller_name is not specified, defaults to raspberrypi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set SETUP_SCRIPT path before sourcing (use absolute path to be safe)
SETUP_SCRIPT="$(cd "$SCRIPT_DIR" && pwd)/on-controller/setup.sh"

# Determine which controller to set up
if [ $# -eq 0 ]; then
    CONTROLLER_NAME="${CONTROLLER_NAME:-raspberrypi}"
else
    if [[ "$1" != "raspberrypi" ]] && [[ "$1" != "steamdeck" ]]; then
        echo "Error: Invalid controller name: $1" >&2
        echo "Valid controllers: raspberrypi, steamdeck" >&2
        exit 1
    fi
    export CONTROLLER_NAME="$1"
fi

source "$SCRIPT_DIR/lib/controller-common.sh"

get_controller_info "$CONTROLLER_NAME"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Setting up $CONTROLLER_NAME Controller Remotely${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Test SSH access (allow password authentication during setup)
log_step "Testing SSH connection to $CONTROLLER_NAME..."
log_info "You may be prompted for a password..."
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}" "echo 'SSH connection successful'" 2>/dev/null; then
    log_error "Cannot connect to controller at ${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}"
    log_info ""
    log_info "Make sure:"
    log_info "  1. NordVPN Meshnet is enabled on both devices"
    log_info "  2. SSH is working: ssh ${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}"
    log_info "  3. Controller hostname is set correctly in controller-config.sh"
    exit 1
fi

log_success "SSH connection verified"

# Copy setup script to controller
log_step "Copying setup script to controller..."
TMP_SCRIPT="/tmp/setup-controller-$$.sh"

# Verify setup script exists
if [ ! -f "$SETUP_SCRIPT" ]; then
    log_error "Setup script not found: $SETUP_SCRIPT"
    log_info "Looking for: $SETUP_SCRIPT"
    log_info "Script directory: $SCRIPT_DIR"
    exit 1
fi

# Use rsync directly (bypass check_controller_connection for setup phase)
rsync -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
    -avz --progress \
    "$SETUP_SCRIPT" \
    "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}:${TMP_SCRIPT}"

# Run setup script on controller
log_step "Running setup script on controller..."
log_info "This will set up directories and verify NordVPN Meshnet..."
log_info ""

# Run setup script (use SSH directly to allow password if needed)
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}" "bash $TMP_SCRIPT"

# Clean up
log_step "Cleaning up..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}" "rm -f $TMP_SCRIPT"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Remote Setup Complete!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "Next step: Deploy controller software"
log_info "  make controller-update"
log_info ""

