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

if [ -z "$ARCHIVE_PATH" ] || [ ! -f "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2
    exit 1
fi

# Extract tegraflash archive
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR" || exit 1
tar -xzf "$ARCHIVE_PATH"

if [ ! -f "./doflash.sh" ]; then
    echo "ERROR: doflash.sh not found in tegraflash archive" >&2
    exit 1
fi

chmod +x ./*.sh 2>/dev/null || true

# Run flashing in Docker container
docker run --rm -it \
    --privileged \
    -v "$TMPDIR:/workspace" \
    -w /workspace \
    --device=/dev/bus/usb \
    "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG" bash -c "
    apt-get update -qq && \
    apt-get install -y -qq device-tree-compiler python3 sudo udev usbutils >/dev/null 2>&1 && \
    sudo ./doflash.sh
"

