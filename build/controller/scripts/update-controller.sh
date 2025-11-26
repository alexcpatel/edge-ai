#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Update controller: deploy both Docker image and scripts
# This is the main script to update the controller software

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Updating Controller Software${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Deploy scripts first (needed for Docker deployment)
"$SCRIPT_DIR/deploy-scripts.sh"

# Deploy Docker image
"$SCRIPT_DIR/deploy-docker-image.sh"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Controller Update Complete!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

