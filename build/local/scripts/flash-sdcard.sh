#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash SD card with Yocto image (macOS only)
# Usage: flash-sdcard.sh [SD_CARD_DEVICE]
#   If SD_CARD_DEVICE is not provided, will create SD card image file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/build/remote/config/aws-config.sh"
source "$REPO_ROOT/build/yocto/config/yocto-config.sh"

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

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script only works on macOS"
    exit 1
fi

# Find tegraflash archive locally
LOCAL_TEGRAFLASH_DIR="$REPO_ROOT/build/local/tegraflash"
TEGRAFLASH_ARCHIVE=$(find "$LOCAL_TEGRAFLASH_DIR" -maxdepth 1 -name "*.tegraflash.tar.gz" -type f 2>/dev/null | sort -r | head -1)

if [ -z "$TEGRAFLASH_ARCHIVE" ]; then
    log_error "Tegraflash archive not found locally."
    log_info "Download it first: make download-tegraflash"
    exit 1
fi

log_info "Using tegraflash archive: $(basename "$TEGRAFLASH_ARCHIVE")"

# Create temporary directory for extraction
TMPDIR=$(mktemp -d)
trap 'log_info "Cleaning up..."; rm -rf "$TMPDIR"' EXIT

log_info "Extracting tegraflash archive..."
tar -xzf "$TEGRAFLASH_ARCHIVE" -C "$TMPDIR"

cd "$TMPDIR"

if [ ! -f "./dosdcard.sh" ]; then
    log_error "dosdcard.sh not found in tegraflash archive"
    exit 1
fi

chmod +x ./*.sh 2>/dev/null || true

SD_CARD_DEVICE="${1:-}"

if [ -z "$SD_CARD_DEVICE" ]; then
    # Interactive device selection with useful info
    log_info ""
    log_info "${BOLD}Available disks:${NC}"
    log_info ""

    # Get physical disks and filter for likely SD cards (Secure Digital protocol)
    AVAILABLE_DISKS=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^/dev/disk[0-9]+.*\(.*physical\) ]] && [[ ! "$line" =~ synthesized ]]; then
            DISK=$(echo "$line" | awk '{print $1}')
            if [[ "$DISK" != "/dev/disk0" ]]; then
                # Check if it's a Secure Digital device (SD card)
                DISK_INFO=$(diskutil info "$DISK" 2>/dev/null)
                PROTOCOL=$(echo "$DISK_INFO" | grep "Protocol" | cut -d: -f2 | xargs || echo "")
                if [[ "$PROTOCOL" == "Secure Digital" ]]; then
                    AVAILABLE_DISKS+=("$DISK")
                fi
            fi
        fi
    done < <(diskutil list)

    # Show each likely SD card with useful info
    INDEX=1
    for disk in "${AVAILABLE_DISKS[@]}"; do
        DISK_INFO=$(diskutil info "$disk" 2>/dev/null)
        NAME=$(echo "$DISK_INFO" | grep "Device / Media Name" | cut -d: -f2 | xargs || echo "Unknown")
        SIZE=$(echo "$DISK_INFO" | grep "Disk Size" | cut -d: -f2 | xargs || echo "Unknown")
        PROTOCOL=$(echo "$DISK_INFO" | grep "Protocol" | cut -d: -f2 | xargs || echo "Unknown")

        log_info "  [$INDEX] $disk"
        log_info "      Name: $NAME"
        log_info "      Size: $SIZE"
        log_info "      Protocol: $PROTOCOL"
        log_info ""
        ((INDEX++))
    done

    if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
        log_error "No external disks found. Please insert your SD card."
        exit 1
    fi

    log_info "${YELLOW}Enter the number of the SD card device (or Ctrl+C to cancel):${NC}"
    read -p "Device number: " SELECTION

    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#AVAILABLE_DISKS[@]} ]; then
        log_error "Invalid selection: $SELECTION"
        exit 1
    fi

    SD_CARD_DEVICE="${AVAILABLE_DISKS[$((SELECTION-1))]}"
    log_info ""
    log_success "Selected: $SD_CARD_DEVICE"
    log_info ""
fi

# Flash directly to SD card
if [ -n "$SD_CARD_DEVICE" ]; then
    log_info ""
    log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    log_info "${BOLD}  PRE-FLASHING VERIFICATION${NC}"
    log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    log_info ""
    log_step "Selected device: $SD_CARD_DEVICE"
    log_info ""

    # On macOS, check if device exists
    if [ ! -e "$SD_CARD_DEVICE" ]; then
        log_error "SD card device not found: $SD_CARD_DEVICE"
        log_info ""
        log_info "Available disks:"
        diskutil list | grep -E "^/dev/disk" || true
        log_info ""
        log_info "Use 'diskutil list' to find your SD card and specify the correct device"
        exit 1
    fi

    # Show disk info for confirmation
    log_info "Device information:"
    diskutil info "$SD_CARD_DEVICE" | grep -E "(Device / Media Name|Disk Size|File System)" || true
    log_info ""
    log_info "${YELLOW}When you have verified this is the correct device, press Enter to continue...${NC}"
    read -p "Press Enter to proceed with flashing, or Ctrl+C to cancel..."

    # Unmount the device first (macOS requirement)
    log_info ""
    log_info "Unmounting SD card..."
    diskutil unmountDisk "$SD_CARD_DEVICE" 2>/dev/null || true

    # Get the raw device (rdisk on macOS) - faster for dd operations
    RAW_DEVICE="${SD_CARD_DEVICE/disk/rdisk}"

    if [ ! -e "$RAW_DEVICE" ]; then
        log_error "Raw device not found: $RAW_DEVICE"
        exit 1
    fi

    log_info ""
    log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    log_info "${BOLD}  STARTING FLASH PROCESS${NC}"
    log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    log_info "Device: $SD_CARD_DEVICE (raw: $RAW_DEVICE)"
    log_info "This may take several minutes. Please be patient..."
    log_info ""

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi

    # Use the same Docker image as the controller (build it if needed)
    DOCKER_IMAGE_NAME="edge-ai-flasher"
    DOCKER_IMAGE_TAG="latest"
    DOCKER_DIR="$REPO_ROOT/build/docker"

    # Always rebuild to capture Dockerfile changes
    log_info "Building Docker image for linux/amd64 (required for tegraflash tools)..."
    if [ ! -f "$DOCKER_DIR/Dockerfile" ]; then
        log_error "Dockerfile not found at $DOCKER_DIR/Dockerfile"
        exit 1
    fi
    cd "$DOCKER_DIR"

    # Build for amd64 platform (required for tegraflash tools)
    if docker buildx version >/dev/null 2>&1; then
        docker buildx create --use --name multiarch 2>/dev/null || docker buildx use multiarch 2>/dev/null || true
        docker buildx build --platform linux/amd64 -t "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" --load .
    else
        log_info "buildx not available, using default build..."
        docker build -t "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" .
    fi
    cd - >/dev/null
    log_success "Docker image built"

    # On macOS, we need to use the raw device and pass it to Docker
    # Docker on macOS can access block devices with --device flag
    docker run --rm -it \
        --privileged \
        -v "$TMPDIR:/workspace" \
        --device "$RAW_DEVICE" \
        -w /workspace \
        "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" bash -c "
        ./dosdcard.sh $(basename "$RAW_DEVICE")
    "

    log_info ""
    log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    log_success "${BOLD}  FLASH COMPLETED SUCCESSFULLY!${NC}"
    log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    log_info ""
fi

