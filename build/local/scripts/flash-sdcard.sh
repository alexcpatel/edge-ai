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

    # Check if image exists, build if not
    if ! docker image inspect "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" >/dev/null 2>&1; then
        log_info "Docker image not found. Building it..."
        if [ ! -f "$DOCKER_DIR/Dockerfile" ]; then
            log_error "Dockerfile not found at $DOCKER_DIR/Dockerfile"
            exit 1
        fi
        cd "$DOCKER_DIR"
        docker build -t "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" .
        cd - >/dev/null
        log_success "Docker image built"
    fi

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
    log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    log_info "${BOLD}  POST-FLASHING SETUP - Follow these steps to boot your device${NC}"
    log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    log_info ""
    log_step "1. Eject the SD card safely:"
    log_info "   - Run: diskutil eject $SD_CARD_DEVICE"
    log_info "   - Or use Finder to eject the SD card"
    log_info ""
    log_step "2. Remove the SD card from your Mac"
    log_info ""
    log_step "3. Configure the Jetson device for SD card boot:"
    log_info "   - Power off the Jetson device completely"
    log_info "   - Locate the boot mode configuration on your Jetson board"
    log_info "   - Set the board to boot from SD card (refer to your board's documentation)"
    log_info "   - For Jetson Orin Nano: Ensure boot mode is set to SD card boot"
    log_info ""
    log_step "4. Insert the flashed SD card into the Jetson device:"
    log_info "   - Insert the SD card into the SD card slot on the Jetson board"
    log_info "   - Make sure it's fully inserted"
    log_info ""
    log_step "5. Connect peripherals to the Jetson board:"
    log_info "   - Connect a monitor via HDMI or DisplayPort"
    log_info "   - Connect a USB keyboard"
    log_info "   - Connect a USB mouse (optional)"
    log_info ""
    log_step "6. Power on the Jetson device:"
    log_info "   - Connect the power adapter to the board"
    log_info "   - Press the POWER button"
    log_info ""
    log_step "7. The device should now boot from the SD card:"
    log_info "   - You should see boot messages on the connected monitor"
    log_info "   - First boot may take longer as the system initializes"
    log_info "   - The system will boot into the Yocto image from the SD card"
    log_info ""
    log_info "${YELLOW}Press Enter when you're ready to exit, or Ctrl+C to cancel...${NC}"
    read -p ""
fi

