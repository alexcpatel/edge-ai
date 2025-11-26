#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Deploy controller scripts to Raspberry Pi
# This script syncs all controller scripts from the repo to the controller

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$SCRIPT_DIR/lib/controller-common.sh"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Deploying Controller Scripts${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Create controller scripts directory on controller
log_step "Setting up directories on controller..."
controller_cmd "mkdir -p $CONTROLLER_BASE_DIR/scripts/lib"
controller_cmd "mkdir -p $CONTROLLER_BASE_DIR/config"

# Sync scripts directory
log_step "Syncing controller scripts..."
CONTROLLER_SCRIPTS_DIR="$REPO_ROOT/build/controller/scripts"
controller_rsync \
    --exclude='*.sh~' \
    --exclude='*.swp' \
    --exclude='.DS_Store' \
    "$CONTROLLER_SCRIPTS_DIR/" \
    "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}:${CONTROLLER_BASE_DIR}/scripts/"

# Sync config directory
log_step "Syncing controller configuration..."
CONTROLLER_CONFIG_DIR="$REPO_ROOT/build/controller/config"
controller_rsync \
    --exclude='*.sh~' \
    --exclude='*.swp' \
    --exclude='.DS_Store' \
    "$CONTROLLER_CONFIG_DIR/" \
    "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}:${CONTROLLER_BASE_DIR}/config/"

# Make scripts executable on controller
log_step "Making scripts executable..."
controller_cmd "chmod +x $CONTROLLER_BASE_DIR/scripts/*.sh"
controller_cmd "chmod +x $CONTROLLER_BASE_DIR/scripts/lib/*.sh 2>/dev/null || true"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Controller Scripts Deployed Successfully!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "Scripts location: $CONTROLLER_BASE_DIR/scripts/"
log_info "Config location: $CONTROLLER_BASE_DIR/config/"

