#!/bin/bash
# Raspberry Pi Controller Configuration
# Edit these values according to your setup

# Tailscale Configuration
# Set the Tailscale hostname or IP of your Raspberry Pi
export CONTROLLER_HOSTNAME="controller"  # Change to your Tailscale hostname
export CONTROLLER_USER="controller"  # Default Raspberry Pi user, change if different

# Controller paths
export CONTROLLER_BASE_DIR="/home/${CONTROLLER_USER}/edge-ai-controller"
export CONTROLLER_TEGRAFLASH_DIR="${CONTROLLER_BASE_DIR}/tegraflash"
export CONTROLLER_IMAGES_DIR="${CONTROLLER_BASE_DIR}/images"

# Docker Configuration
export DOCKER_IMAGE_NAME="edge-ai-flasher"
export DOCKER_IMAGE_TAG="latest"

