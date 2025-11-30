#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Setup script for controllers
# This script sets up the controller environment
# Usage: Run this script on the controller (not from your laptop)

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

# Detect controller type based on hostname
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
if [[ "$HOSTNAME" == *"raspberrypi"* ]] || [[ "$HOSTNAME" == *"raspberry"* ]]; then
    CONTROLLER_TYPE="raspberrypi"
    CONTROLLER_PURPOSE="serial debug access"
elif [[ "$HOSTNAME" == *"steamdeck"* ]] || [[ "$HOSTNAME" == *"deck"* ]]; then
    CONTROLLER_TYPE="steamdeck"
    CONTROLLER_PURPOSE="flash-usb operations"
else
    CONTROLLER_TYPE="unknown"
    CONTROLLER_PURPOSE="controller operations"
fi

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Setting up $CONTROLLER_TYPE Controller${NC}"
log_info "${BOLD}  Purpose: $CONTROLLER_PURPOSE${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Function to check and install required packages for flashing (steamdeck only)
check_flash_packages() {
    if [ "$CONTROLLER_TYPE" != "steamdeck" ]; then
        return 0
    fi

    log_step "Checking required packages for flashing..."

    # Required packages based on Dockerfile
    REQUIRED_PACKAGES=(
        device-tree-compiler
        python3
        python3-yaml
        sudo
        udev
        usbutils
        rsync
        file
        libc6-i386
        libstdc++6:i386
        gawk
        wget
        git-core
        diffstat
        unzip
        texinfo
        gcc-multilib
        build-essential
        chrpath
        socat
        libsdl1.2-dev
        xterm
        zstd
        gdisk
    )

    MISSING_PACKAGES=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        # Handle multiarch packages (i386)
        if [[ "$pkg" == *":i386" ]]; then
            pkg_name="${pkg%:*}"
            if ! dpkg -l | grep -q "^ii.*$pkg_name.*i386" 2>/dev/null; then
                MISSING_PACKAGES+=("$pkg")
            fi
        else
            if ! dpkg -l | grep -q "^ii.*$pkg " 2>/dev/null; then
                MISSING_PACKAGES+=("$pkg")
            fi
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
        log_success "All required packages are installed"
    else
        log_info "Installing missing packages..."
        if command -v apt-get &> /dev/null; then
            # Enable multiarch support for i386 packages
            if ! dpkg --print-architecture | grep -q i386 2>/dev/null; then
                sudo dpkg --add-architecture i386
            fi
            sudo apt-get update -qq
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING_PACKAGES[@]}"
            log_success "Required packages installed"
        else
            log_error "Cannot install packages automatically. Please install: ${MISSING_PACKAGES[*]}"
            return 1
        fi
    fi
}

# Create directories
log_step "Creating directories..."
mkdir -p "$CONTROLLER_TEGRAFLASH_DIR"
log_success "Directories created"

# Check and install flash packages for steamdeck
check_flash_packages

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
if [ "$CONTROLLER_TYPE" = "steamdeck" ]; then
    log_info "Next steps (on your laptop):"
    log_info "  1. Make sure NordVPN Meshnet is enabled on both devices"
    log_info "  2. Deploy controller software: make controller-update steamdeck"
    log_info "  3. Push tegraflash archive: make controller-push-tegraflash"
else
    log_info "Next steps (on your laptop):"
    log_info "  1. Make sure NordVPN Meshnet is enabled on both devices"
    log_info "  2. Controller is ready for serial debug access"
fi
log_info ""

