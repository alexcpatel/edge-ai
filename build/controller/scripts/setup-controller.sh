#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Setup script for Raspberry Pi controller
# This script should be run on the Raspberry Pi to set up the flashing environment
# Usage: Run this script on the Raspberry Pi (not from your laptop)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_error() { echo -e "${RED}$*${NC}"; }
log_step() { echo -e "${BLUE}${BOLD}→ $*${NC}"; }

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Do not run this script as root. It will use sudo when needed."
    exit 1
fi

CONTROLLER_USER="${SUDO_USER:-$USER}"
CONTROLLER_BASE_DIR="$HOME/edge-ai-controller"
CONTROLLER_TEGRAFLASH_DIR="$CONTROLLER_BASE_DIR/tegraflash"
DOCKER_IMAGE_NAME="edge-ai-flasher"
DOCKER_IMAGE_TAG="latest"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Setting up Raspberry Pi Controller for Edge AI Flashing${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Check for Docker
log_step "Checking for Docker..."
if ! command -v docker &> /dev/null; then
    log_info "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    sudo usermod -aG docker "$CONTROLLER_USER"
    log_success "Docker installed. You may need to log out and back in for group changes to take effect."
else
    log_success "Docker is installed"
fi

# Check if user is in docker group
if ! groups | grep -q docker; then
    log_info "Adding user to docker group..."
    sudo usermod -aG docker "$CONTROLLER_USER"
    log_info "User added to docker group. You may need to log out and back in."
fi

# Create directories
log_step "Creating directories..."
mkdir -p "$CONTROLLER_TEGRAFLASH_DIR"
log_success "Directories created"

# Note: Docker image should be deployed from your laptop
log_step "Docker image setup..."
log_info "Docker image will be deployed from your laptop using:"
log_info "  make controller-update"
log_info "This ensures the image is built with the latest code from your repository."

# Check Tailscale
log_step "Checking Tailscale..."
if ! command -v tailscale &> /dev/null; then
    log_info "Tailscale not found. Please install Tailscale:"
    log_info "  curl -fsSL https://tailscale.com/install.sh | sh"
    log_info "  sudo tailscale up"
else
    log_success "Tailscale is installed"
    log_info "Make sure Tailscale is running: sudo tailscale status"
fi

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Setup Complete!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "Next steps (on your laptop):"
log_info "  1. Make sure Tailscale is running on both devices"
log_info "  2. Note your Tailscale hostname: tailscale status | grep $(hostname)"
log_info "  3. Update CONTROLLER_HOSTNAME in build/controller/config/controller-config.sh"
log_info "  4. Test connection from your laptop: ping <your-tailscale-hostname>"
log_info "  5. Deploy controller software: make controller-update"
log_info ""

