#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Update controller: deploy both Docker image and scripts
# This is the main script to update the controller software

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Save script paths before sourcing (which may change SCRIPT_DIR)
DEPLOY_SCRIPTS="$SCRIPT_DIR/deploy-scripts.sh"
DEPLOY_DOCKER="$SCRIPT_DIR/deploy-docker-image.sh"

source "$SCRIPT_DIR/lib/controller-common.sh"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Updating Controller Software${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Deploy scripts first (needed for Docker deployment)
"$DEPLOY_SCRIPTS"

# Deploy Docker image
"$DEPLOY_DOCKER"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Controller Update Complete!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

