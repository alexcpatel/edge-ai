#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Build and deploy Docker image to Raspberry Pi controller
# This script builds the Docker image on your laptop and transfers it to the controller

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$SCRIPT_DIR/lib/controller-common.sh"

log_info ""
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info "${BOLD}  Building and Deploying Docker Image to Controller${NC}"
log_info "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""

# Check Docker is available locally
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed on your laptop"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Build Docker image locally
DOCKER_DIR="$REPO_ROOT/build/controller/docker"
if [ ! -f "$DOCKER_DIR/Dockerfile" ]; then
    log_error "Dockerfile not found at $DOCKER_DIR/Dockerfile"
    exit 1
fi

log_step "Building Docker image locally..."
cd "$DOCKER_DIR"

# Tegraflash scripts require x86_64/amd64 architecture
# Build for amd64 even if running on ARM (Docker will use emulation)
log_info "Building for x86_64/amd64 (required for tegraflash tools)..."

# Use buildx if available for explicit platform specification
if docker buildx version >/dev/null 2>&1; then
    log_info "Using buildx to build for linux/amd64..."
    # Create builder if it doesn't exist
    docker buildx create --use --name multiarch 2>/dev/null || docker buildx use multiarch 2>/dev/null || true
    docker buildx build --platform linux/amd64 -t "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG" --load .
else
    log_info "Building with default docker build (will use host architecture)..."
    log_info "Note: If buildx is not available, ensure Docker Desktop supports multi-arch"
    docker build -t "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG" .
fi

log_success "Docker image built: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG (linux/amd64)"

# Save Docker image to tar file
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

IMAGE_TAR="$TMPDIR/${DOCKER_IMAGE_NAME}-${DOCKER_IMAGE_TAG}.tar"
log_step "Saving Docker image to tar file..."
docker save "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG" -o "$IMAGE_TAR"
log_success "Docker image saved: $(basename "$IMAGE_TAR")"

# Transfer to controller
log_step "Transferring Docker image to controller..."
log_info "This may take a few minutes depending on your connection speed..."

# Ensure controller has directory for temporary image storage
controller_cmd "mkdir -p $CONTROLLER_BASE_DIR/tmp"

# Transfer the image tar
IMAGE_NAME=$(basename "$IMAGE_TAR")
controller_rsync "$IMAGE_TAR" "${CONTROLLER_USER}@${CONTROLLER_HOSTNAME}:${CONTROLLER_BASE_DIR}/tmp/"

# Load image on controller
log_step "Loading Docker image on controller..."
controller_cmd "docker load -i ${CONTROLLER_BASE_DIR}/tmp/$IMAGE_NAME"

# Clean up on controller
log_step "Cleaning up temporary files on controller..."
controller_cmd "rm -f ${CONTROLLER_BASE_DIR}/tmp/$IMAGE_NAME"

log_info ""
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_success "${BOLD}  Docker Image Deployed Successfully!${NC}"
log_success "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
log_info ""
log_info "Image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
log_info "Location: Controller (Raspberry Pi)"

