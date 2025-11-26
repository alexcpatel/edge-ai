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

# Check for QEMU emulation support (needed for x86_64 containers on ARM)
log_step "Checking for QEMU emulation support..."
if [ "$(uname -m)" != "x86_64" ] && [ "$(uname -m)" != "amd64" ]; then
    if ! docker run --rm --platform linux/amd64 ubuntu:22.04 uname -m >/dev/null 2>&1; then
        log_info "QEMU emulation not available. Installing qemu-user-static..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq qemu-user-static binfmt-support
            log_success "QEMU emulation installed"
        else
            log_error "Cannot install QEMU automatically. Please install qemu-user-static manually."
            log_info "On Debian/Ubuntu: sudo apt-get install qemu-user-static binfmt-support"
        fi
    else
        log_success "QEMU emulation is working"
    fi
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

# Check NordVPN Meshnet
log_step "Checking NordVPN Meshnet..."
if ! command -v nordvpn &> /dev/null; then
    log_info "NordVPN not found. Please install NordVPN:"
    log_info "  curl -fsSL https://downloads.nordcdn.com/apps/linux/install.sh | sh"
    log_info "  nordvpn login"
    log_info "  nordvpn set meshnet on"
else
    log_success "NordVPN is installed"
    log_info "Make sure Meshnet is enabled: nordvpn meshnet peer list"
    if ! nordvpn meshnet peer list >/dev/null 2>&1; then
        log_info "Enable Meshnet with: nordvpn set meshnet on"
    fi
fi

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Setup Complete!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "Next steps (on your laptop):"
log_info "  1. Make sure NordVPN Meshnet is enabled on both devices"
log_info "  2. Find your Meshnet hostname/IP: nordvpn meshnet peer list"
log_info "  3. Update CONTROLLER_HOSTNAME in build/controller/config/controller-config.sh"
log_info "  4. Test connection from your laptop: ping <meshnet-hostname-or-ip>"
log_info "  5. Deploy controller software: make controller-update"
log_info ""

