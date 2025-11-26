#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flash device script - runs on the controller
# This script is deployed to the controller and executed remotely

# This script runs on the controller (Raspberry Pi)
# Source config from the controller's base directory
CONTROLLER_BASE_DIR="${CONTROLLER_BASE_DIR:-/home/controller/edge-ai-controller}"
source "$CONTROLLER_BASE_DIR/config/controller-config.sh"

ARCHIVE_PATH="$1"

if [ -z "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive path not provided" >&2
    exit 1
fi

# Check if file exists
if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive file not found: $ARCHIVE_PATH" >&2
    echo "Looking in: $CONTROLLER_TEGRAFLASH_DIR" >&2
    ls -la "$CONTROLLER_TEGRAFLASH_DIR" >&2 || true
    exit 1
fi

# Verify it's actually a gzip file
if ! file "$ARCHIVE_PATH" | grep -q "gzip"; then
    echo "ERROR: File does not appear to be a gzip archive: $ARCHIVE_PATH" >&2
    file "$ARCHIVE_PATH" >&2
    exit 1
fi

# Extract tegraflash archive to persistent directory for debugging
ARCHIVE_NAME=$(basename "$ARCHIVE_PATH" .tegraflash.tar.gz)
EXTRACT_DIR="$CONTROLLER_BASE_DIR/tegraflash-extracted/$ARCHIVE_NAME"
EXTRACT_MARKER="$EXTRACT_DIR/.extracted-from"
NEEDS_EXTRACT=true

# Check if already extracted and archive hasn't changed
if [ -d "$EXTRACT_DIR" ] && [ -f "$EXTRACT_MARKER" ]; then
    MARKED_ARCHIVE=$(cat "$EXTRACT_MARKER" 2>/dev/null || echo "")
    if [ "$MARKED_ARCHIVE" = "$ARCHIVE_PATH" ]; then
        # Check if archive file still exists and hasn't been modified
        if [ -f "$ARCHIVE_PATH" ]; then
            ARCHIVE_MTIME=$(stat -c %Y "$ARCHIVE_PATH" 2>/dev/null || stat -f %m "$ARCHIVE_PATH" 2>/dev/null || echo "0")
            EXTRACT_MTIME=$(stat -c %Y "$EXTRACT_MARKER" 2>/dev/null || stat -f %m "$EXTRACT_MARKER" 2>/dev/null || echo "0")
            if [ "$EXTRACT_MTIME" -ge "$ARCHIVE_MTIME" ]; then
                echo "Archive already extracted, skipping extraction..."
                NEEDS_EXTRACT=false
            fi
        fi
    fi
fi

if [ "$NEEDS_EXTRACT" = true ]; then
    echo "Extracting archive to: $EXTRACT_DIR"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    cd "$EXTRACT_DIR" || exit 1

    tar -xzf "$ARCHIVE_PATH"

    if [ ! -f "./doflash.sh" ]; then
        echo "ERROR: doflash.sh not found in tegraflash archive" >&2
        exit 1
    fi

    # Mark what archive this was extracted from
    echo "$ARCHIVE_PATH" > "$EXTRACT_MARKER"
    chmod +x ./*.sh 2>/dev/null || true
    echo "Extraction complete"
else
    cd "$EXTRACT_DIR" || exit 1
fi

# Debug: Check architectures
echo "=== Architecture Debug Info ==="
echo "Host architecture (Raspberry Pi): $(uname -m)"
echo "Docker container architecture:"
docker run --rm --platform linux/amd64 "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG" uname -m || true
echo "Tegraflash binary info:"
file "$EXTRACT_DIR/tegrarcm_v2" 2>/dev/null || echo "tegrarcm_v2 not found"
ls -la "$EXTRACT_DIR/tegrarcm_v2" 2>/dev/null || true
echo "==============================="

# Run flashing in Docker container
# Use -it only if TTY is available, otherwise use -i (for stdin) or no flags
if [ -t 0 ] && [ -t 1 ]; then
    DOCKER_TTY_FLAGS="-it"
elif [ -t 0 ]; then
    DOCKER_TTY_FLAGS="-i"
else
    DOCKER_TTY_FLAGS=""
fi

# Check if QEMU emulation is available before running x86_64 container
if [ "$(uname -m)" != "x86_64" ] && [ "$(uname -m)" != "amd64" ]; then
    echo "Checking QEMU emulation support..."
    if ! docker run --rm --platform linux/amd64 ubuntu:22.04 echo "QEMU working" >/dev/null 2>&1; then
        echo "ERROR: QEMU emulation is not available. Cannot run x86_64 containers on ARM." >&2
        echo "Install QEMU emulation with:" >&2
        echo "  sudo apt-get install qemu-user-static binfmt-support" >&2
        echo "Or run: make controller-setup (which should install it)" >&2
        exit 1
    fi
fi

# Check for NVIDIA USB device before running
echo "Checking for NVIDIA USB device on host..."
if ! lsusb | grep -i nvidia >/dev/null 2>&1; then
    echo "WARNING: No NVIDIA USB device detected. Make sure device is in recovery mode." >&2
    echo "Run 'lsusb | grep -i nvidia' to verify device is connected." >&2
fi

# Run Docker container with explicit amd64 platform (required for tegraflash tools)
# Use -v /dev:/dev to give full access to USB devices (with --privileged for permissions)
docker run --rm $DOCKER_TTY_FLAGS \
    --platform linux/amd64 \
    --privileged \
    -v "$EXTRACT_DIR:/workspace" \
    -v /dev:/dev \
    -w /workspace \
    "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG" bash -c "
    echo 'Container architecture:' \$(uname -m)
    echo 'Checking USB devices in container...'
    lsusb | grep -i nvidia || echo 'No NVIDIA device found in container'
    echo 'Binary architecture:'
    file /workspace/tegrarcm_v2 2>/dev/null || echo 'tegrarcm_v2 not found'
    echo '---'
    # All packages should already be installed in the Docker image
    # Just run the flash script
    sudo ./doflash.sh
"

