#!/bin/bash
# Deploy squirrel-cam ML pipeline to device
#
# Usage: ./deploy.sh <device>
#
# Deploys 3 containers:
#   - go2rtc:    RTSP proxy for Blink cameras
#   - deepstream: GPU inference
#   - app:       Detection event handler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()      { echo "[squirrel-cam] $*"; }
log_ok()   { echo "[squirrel-cam] ✓ $*"; }
die()      { echo "[squirrel-cam] ERROR: $*" >&2; exit 1; }

DEVICE="${1:-}"
[ -z "$DEVICE" ] && die "Usage: $0 <device-ip-or-hostname>"

ssh_cmd() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "root@${DEVICE}" "$@"
}

# Check connectivity and nvidia runtime
log "Checking device..."
ssh_cmd "true" || die "Cannot reach device: $DEVICE"
ssh_cmd "docker info 2>/dev/null | grep -q 'nvidia'" || die "nvidia runtime not configured in docker"
log_ok "Device ready"

# Setup directories
ssh_cmd "
    mkdir -p /data/sandbox/squirrel-cam/models
    mkdir -p /tmp/squirrel-sock
    docker network create squirrel-net 2>/dev/null || true
"

# Deploy go2rtc and app (cross-compiled on dev machine)
deploy_container() {
    local name="$1"
    local build_dir="$2"
    local image="sandbox/$name:dev"
    local container="sandbox-$name"

    log "Building $name..."
    docker buildx build --platform linux/arm64 -t "$image" --load "$build_dir" -q >/dev/null

    log "Deploying $name..."
    docker save "$image" | gzip | ssh_cmd "docker load >/dev/null"
    ssh_cmd "docker stop '$container' 2>/dev/null; docker rm '$container' 2>/dev/null" || true
    log_ok "$name"
}

deploy_container "squirrel-go2rtc" "$SCRIPT_DIR/go2rtc"
deploy_container "squirrel-app" "$SCRIPT_DIR"

# Deploy deepstream (must build on device - L4T images are Jetson-only)
deploy_deepstream() {
    local image="sandbox/squirrel-deepstream:dev"
    local container="sandbox-deepstream"

    log "Syncing deepstream to device..."
    rsync -az --delete -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q" \
        "$SCRIPT_DIR/deepstream/" "root@${DEVICE}:/tmp/deepstream-build/"

    log "Building deepstream on device (~10min first time)..."
    ssh_cmd "
        cd /tmp/deepstream-build
        docker build -t '$image' . >/dev/null
        rm -rf /tmp/deepstream-build
        docker stop '$container' 2>/dev/null || true
        docker rm '$container' 2>/dev/null || true
    " || die "DeepStream build failed"
    log_ok "deepstream"
}

deploy_deepstream

# Start containers
log "Starting containers..."

ssh_cmd "docker run -d --name sandbox-go2rtc --restart unless-stopped \
    --network squirrel-net -p 8554:8554 -p 1984:1984 \
    sandbox/squirrel-go2rtc:dev >/dev/null 2>&1" || true

ssh_cmd "docker run -d --name sandbox-deepstream --restart unless-stopped \
    --network squirrel-net --runtime nvidia -p 8555:8555 \
    -v /data/sandbox/squirrel-cam/models:/models \
    -v /tmp/squirrel-sock:/tmp \
    -e SOURCE_URI=rtsp://sandbox-go2rtc:8554/test \
    sandbox/squirrel-deepstream:dev >/dev/null 2>&1" || true

ssh_cmd "docker run -d --name sandbox-squirrel-app --restart unless-stopped \
    --network squirrel-net \
    -v /tmp/squirrel-sock:/tmp \
    sandbox/squirrel-app:dev >/dev/null 2>&1" || true

log_ok "All containers started"

# Status
log ""
log "Streams:"
log "  Raw:       vlc rtsp://$DEVICE:8554/test"
log "  Detection: vlc rtsp://$DEVICE:8555/ds"
log "  go2rtc UI: http://$DEVICE:1984"
log ""
log "Logs:"
log "  ssh root@$DEVICE 'docker logs -f sandbox-deepstream'"
