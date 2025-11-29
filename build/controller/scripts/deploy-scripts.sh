#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Deploy controller scripts to a controller
# This script syncs all controller scripts from the repo to the controller
# Usage: ./deploy-scripts.sh [controller_name]
#   Defaults to steamdeck (used for flash operations)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Determine which controller to deploy to
if [ $# -eq 0 ]; then
    # Default to steamdeck for flash operations
    export CONTROLLER_NAME="steamdeck"
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
log_info "${BOLD}  Deploying Controller Scripts to $CONTROLLER_NAME${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Create controller scripts directory on controller
log_step "Setting up directories on controller..."
controller_cmd "$CONTROLLER_NAME" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/scripts/lib"
controller_cmd "$CONTROLLER_NAME" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller"
controller_cmd "$CONTROLLER_NAME" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/config"

# Sync scripts directory (exclude on-controller, synced separately)
log_step "Syncing controller scripts..."
CONTROLLER_SCRIPTS_DIR="$REPO_ROOT/build/controller/scripts"
controller_rsync "$CONTROLLER_NAME" \
    --exclude='*.sh~' \
    --exclude='*.swp' \
    --exclude='.DS_Store' \
    --exclude='on-controller/' \
    "$CONTROLLER_SCRIPTS_DIR/" \
    "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}:$CURRENT_CONTROLLER_BASE_DIR/scripts/"

# Sync config directory
log_step "Syncing controller configuration..."
CONTROLLER_CONFIG_DIR="$REPO_ROOT/build/controller/config"
controller_rsync "$CONTROLLER_NAME" \
    --exclude='*.sh~' \
    --exclude='*.swp' \
    --exclude='.DS_Store' \
    "$CONTROLLER_CONFIG_DIR/" \
    "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}:$CURRENT_CONTROLLER_BASE_DIR/config/"

# Sync on-controller scripts
log_step "Syncing on-controller scripts..."
ON_CONTROLLER_SCRIPTS_DIR="$REPO_ROOT/build/controller/scripts/on-controller"
controller_rsync "$CONTROLLER_NAME" \
    --exclude='*.sh~' \
    --exclude='*.swp' \
    --exclude='.DS_Store' \
    "$ON_CONTROLLER_SCRIPTS_DIR/" \
    "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOSTNAME}:$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/"

# Make scripts executable on controller
log_step "Making scripts executable..."
controller_cmd "$CONTROLLER_NAME" "chmod +x $CURRENT_CONTROLLER_BASE_DIR/scripts/*.sh 2>/dev/null || true"
controller_cmd "$CONTROLLER_NAME" "chmod +x $CURRENT_CONTROLLER_BASE_DIR/scripts/lib/*.sh 2>/dev/null || true"
controller_cmd "$CONTROLLER_NAME" "chmod +x $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/*.sh 2>/dev/null || true"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Controller Scripts Deployed Successfully to $CONTROLLER_NAME!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "Scripts location: $CURRENT_CONTROLLER_BASE_DIR/scripts/"
log_info "Config location: $CURRENT_CONTROLLER_BASE_DIR/config/"

