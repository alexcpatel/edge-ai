#!/bin/bash
# Raspberry Pi Controller Configuration
# This file sources local overrides from controller-config.local.sh if it exists
# Create controller-config.local.sh with your personal settings (it's gitignored)

# Default values (can be overridden in controller-config.local.sh)
export CONTROLLER_HOSTNAME="${CONTROLLER_HOSTNAME:-your-controller-hostname.nord}"
export CONTROLLER_USER="${CONTROLLER_USER:-controller}"

# Controller paths
export CONTROLLER_BASE_DIR="/home/${CONTROLLER_USER}/edge-ai-controller"
export CONTROLLER_TEGRAFLASH_DIR="${CONTROLLER_BASE_DIR}/tegraflash"
export CONTROLLER_IMAGES_DIR="${CONTROLLER_BASE_DIR}/images"

# Docker Configuration
export DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-edge-ai-flasher}"
export DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"

# Source local overrides if they exist
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/controller-config.local.sh" ]; then
    source "$SCRIPT_DIR/controller-config.local.sh"
fi

