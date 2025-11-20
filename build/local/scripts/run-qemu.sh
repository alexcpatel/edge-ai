#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Run Yocto build in QEMU
# Usage: run-qemu.sh [SD_CARD_IMAGE]
#   If SD_CARD_IMAGE is not provided, searches for .img.gz in Downloads folder

# Colors for output (define early so we can use them)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}$*${NC}" >&2; }
log_success() { echo -e "${GREEN}$*${NC}" >&2; }
log_error() { echo -e "${RED}$*${NC}" >&2; }

# Get script directory (works even if script is symlinked)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source configs and common functions for EC2 access
source "$REPO_ROOT/build/remote/config/aws-config.sh"
source "$REPO_ROOT/build/yocto/config/yocto-config.sh"
source "$REPO_ROOT/build/remote/scripts/lib/common.sh"

# Find SD card image
find_sdcard_image() {
    local image_path="$1"

    if [ -n "$image_path" ]; then
        if [ ! -f "$image_path" ]; then
            log_error "SD card image not found: $image_path"
            exit 1
        fi
        echo "$image_path"
        return
    fi

    # Search in Downloads folder
    if [[ "$OSTYPE" == "darwin"* ]]; then
        DOWNLOADS_DIR="$HOME/Downloads"
    else
        DOWNLOADS_DIR="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
    fi

    # Look for the SD card image matching our machine and image
    local image
    image=$(find "$DOWNLOADS_DIR" -maxdepth 1 -name "*${YOCTO_IMAGE}-${YOCTO_MACHINE}*.img.gz" -type f 2>/dev/null | sort -r | head -1)

    if [ -z "$image" ]; then
        log_error "No SD card image found matching ${YOCTO_IMAGE}-${YOCTO_MACHINE}"
        log_error "Expected filename pattern: *${YOCTO_IMAGE}-${YOCTO_MACHINE}*.img.gz"
        log_error "Please download it first: make download-image"
        log_error "Or specify the path: $0 /path/to/image.img.gz"
        exit 1
    fi

    echo "$image"
}

# Check if QEMU is installed
check_qemu() {
    if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
        log_error "qemu-system-aarch64 not found"
        log_info "Install QEMU:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            log_info "  brew install qemu"
            log_info ""
            log_info "Note: QEMU works natively on Apple Silicon (M1/M2/M3) for ARM64 emulation"
        else
            log_info "  sudo apt-get install qemu-system-arm"
        fi
        exit 1
    fi

    # Show QEMU version for debugging
    if [[ "${DEBUG:-}" == "1" ]]; then
        log_info "QEMU version: $(qemu-system-aarch64 --version | head -1)"
    fi
}

# Main execution
main() {
    local image_path="${1:-}"

    log_info "Preparing QEMU environment for Jetson Orin Nano..."

    # Check QEMU is installed
    check_qemu

    # Find SD card image
    local compressed_image
    compressed_image=$(find_sdcard_image "$image_path")
    log_info "Using SD card image: $(basename "$compressed_image")"

    # Decompress the image to a temporary location
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'log_info "Cleaning up temporary directory..."; rm -rf "$tmpdir"' EXIT

    log_info "Decompressing SD card image..."
    local img_name
    img_name=$(basename "$compressed_image" .gz)
    local sdcard_image="$tmpdir/$img_name"

    gunzip -c "$compressed_image" > "$sdcard_image"

    log_success "SD card image ready: $img_name"

    # QEMU configuration
    # Jetson Orin Nano specs:
    # - ARM Cortex-A78AE cores (8 cores)
    # - 8GB RAM (we'll use 4GB for QEMU)
    # - ARMv8.2-A architecture

    local qemu_memory="${QEMU_MEMORY:-4096}"
    local qemu_cpus="${QEMU_CPUS:-4}"
    local qemu_machine="${QEMU_MACHINE:-virt}"

    log_info "Starting QEMU..."
    log_info "  Machine: $qemu_machine"
    log_info "  Memory: ${qemu_memory}M"
    log_info "  CPUs: $qemu_cpus"
    log_info "  Disk: $sdcard_image"
    log_info ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "Running on macOS - QEMU will use native ARM64 emulation"
    fi
    log_info ""
    log_info "Note: QEMU emulates generic ARM64 hardware, not Jetson-specific features"
    log_info "      (GPU, specific peripherals, etc. won't be available)"
    log_info ""
    log_info "Press Ctrl+A then X to exit QEMU"
    log_info "Or use Ctrl+C in another terminal"
    log_info ""

    # Run QEMU
    # Note: For Jetson Orin Nano, we use virt machine type which is generic ARM64
    # The actual Jetson hardware is very specific, so QEMU won't fully emulate it
    # but it should be sufficient for basic testing of the Yocto image
    #
    # On Apple Silicon (M1/M2/M3), QEMU runs natively and can efficiently emulate ARM64
    qemu-system-aarch64 \
        -machine "$qemu_machine",accel=tcg \
        -cpu cortex-a78 \
        -smp "$qemu_cpus" \
        -m "${qemu_memory}M" \
        -drive file="$sdcard_image",format=raw,if=sd,id=sd0 \
        -netdev user,id=net0 \
        -device virtio-net-device,netdev=net0 \
        -nographic \
        -serial stdio \
        -monitor none \
        "$@"
}

main "$@"

