#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Update controller: deploy scripts to controller
# This is the main script to update the controller software
# Usage: ./update-controller.sh [controller_name]
#   Defaults to steamdeck (used for flash operations)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine which controller to update
if [ $# -eq 0 ]; then
    # Default to steamdeck for flash operations
    CONTROLLER_NAME="steamdeck"
else
    if [[ "$1" != "raspberrypi" ]] && [[ "$1" != "steamdeck" ]]; then
        echo "Error: Invalid controller name: $1" >&2
        echo "Valid controllers: raspberrypi, steamdeck" >&2
        exit 1
    fi
    CONTROLLER_NAME="$1"
fi

# Save script path before sourcing (which may change SCRIPT_DIR)
DEPLOY_SCRIPTS="$SCRIPT_DIR/deploy-scripts.sh"

source "$SCRIPT_DIR/lib/controller-common.sh"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Updating $CONTROLLER_NAME Controller Software${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Deploy scripts to controller
"$DEPLOY_SCRIPTS" "$CONTROLLER_NAME"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Controller Update Complete for $CONTROLLER_NAME!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

