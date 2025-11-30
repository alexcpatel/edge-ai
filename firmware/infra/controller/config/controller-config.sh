#!/bin/bash
# Controller Configuration
# This file sources local overrides from controller-config.local.sh if it exists
# Create controller-config.local.sh with your personal settings (it's gitignored)

# Controller definitions
# raspberrypi: Used for remote access to debug serial connections
# steamdeck: Used for flash-usb operations
# Values are set in controller-config.local.sh

# Default controller (for backward compatibility)
export CONTROLLER_NAME="${CONTROLLER_NAME:-raspberrypi}"

# Source local overrides if they exist (before defining functions that use them)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/controller-config.local.sh" ]; then
    source "$SCRIPT_DIR/controller-config.local.sh"
fi

# Helper function to get controller hostname
get_controller_hostname() {
    local controller_name="${1:-$CONTROLLER_NAME}"
    case "$controller_name" in
        raspberrypi)
            echo "${CONTROLLER_RASPBERRYPI_HOSTNAME:-}"
            ;;
        steamdeck)
            echo "${CONTROLLER_STEAMDECK_HOSTNAME:-}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Helper function to get controller user
get_controller_user() {
    local controller_name="${1:-$CONTROLLER_NAME}"
    case "$controller_name" in
        raspberrypi)
            echo "${CONTROLLER_RASPBERRYPI_USER:-}"
            ;;
        steamdeck)
            echo "${CONTROLLER_STEAMDECK_USER:-}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Set current controller variables (for backward compatibility)
CONTROLLER_HOSTNAME="$(get_controller_hostname)"
CONTROLLER_USER="$(get_controller_user)"
export CONTROLLER_HOSTNAME CONTROLLER_USER

# Controller paths (based on current controller)
export CONTROLLER_BASE_DIR="/home/${CONTROLLER_USER}/edge-ai-controller"
export CONTROLLER_TEGRAFLASH_DIR="${CONTROLLER_BASE_DIR}/tegraflash"
export CONTROLLER_IMAGES_DIR="${CONTROLLER_BASE_DIR}/images"

# Docker Configuration
export DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-edge-ai-flasher}"
export DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"

