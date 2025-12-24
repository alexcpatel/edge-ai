#!/bin/bash
# Deploy squirrel-cam ML pipeline to device
#
# Usage: ./deploy.sh <device>
#
# Deploys 3 containers:
#   - go2rtc:    RTSP proxy for Blink cameras
#   - inference: GPU inference with TensorRT
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

# Ensure /data is mounted
ssh_cmd "mountpoint -q /data || mount /data" 2>/dev/null || true

# Configure nvidia runtime if not already
if ! ssh_cmd "docker info 2>/dev/null | grep -q 'nvidia'"; then
    log "Configuring nvidia runtime..."
    ssh_cmd "
        mkdir -p /data/config/docker
        cat > /data/config/docker/daemon.json << 'EOF'
{
    \"data-root\": \"/data/docker\",
    \"runtimes\": {
        \"nvidia\": {
            \"path\": \"nvidia-container-runtime\",
            \"runtimeArgs\": []
        }
    }
}
EOF
        mkdir -p /etc/docker
        mount --bind /data/config/docker /etc/docker 2>/dev/null || cp /data/config/docker/daemon.json /etc/docker/
        systemctl restart docker
        sleep 2
    "
fi
ssh_cmd "docker info 2>/dev/null | grep -q 'nvidia'" || die "Failed to configure nvidia runtime"
log_ok "Device ready"

# Setup directories
ssh_cmd "
    mkdir -p /data/sandbox/squirrel-cam/models
    mkdir -p /tmp/squirrel-sock
    docker network create squirrel-net 2>/dev/null || true
    docker image prune -f >/dev/null 2>&1 || true
"

# Deploy go2rtc and app (cross-compiled on dev machine)
deploy_container() {
    local name="$1"
    local build_dir="$2"
    local image="sandbox/$name:dev"
    local container="sandbox-$name"

    log "Building $name..."
    docker buildx build --builder desktop-linux --platform linux/arm64 -t "$image" --load --progress=plain "$build_dir"

    log "Deploying $name to device..."
    local size_bytes=$(docker image inspect "$image" --format='{{.Size}}')
    local size_mb=$((size_bytes / 1024 / 1024))
    log "  Transferring ${size_mb}MB..."
    docker save "$image" | pv -s "$size_bytes" | gzip | ssh_cmd "docker load"
    ssh_cmd "docker stop '$container' 2>/dev/null; docker rm '$container' 2>/dev/null" || true
    log_ok "$name"
}

deploy_container "squirrel-go2rtc" "$SCRIPT_DIR/go2rtc"
deploy_container "squirrel-app" "$SCRIPT_DIR"

# Inference container - build on device (base image pulled from NGC)
deploy_inference() {
    local base_image="ultralytics/ultralytics:latest-jetson-jetpack6"
    local image="sandbox/squirrel-inference:dev"
    local container="sandbox-inference"

    # Ensure base image exists on device (one-time ~2GB pull)
    if ! ssh_cmd "docker image inspect '$base_image' >/dev/null 2>&1"; then
        log "Pulling L4T JetPack base image on device..."
        NGC_KEY=$(aws ssm get-parameter --name "/edge-ai/ngc-api-key" --with-decryption --query "Parameter.Value" --output text --region us-west-2 2>/dev/null) || die "Failed to get NGC key from SSM"
        ssh_cmd "mkdir -p /data/.docker && export DOCKER_CONFIG=/data/.docker && echo '$NGC_KEY' | docker login nvcr.io -u '\$oauthtoken' --password-stdin"
        ssh_cmd "export DOCKER_CONFIG=/data/.docker && docker pull '$base_image'" || die "Failed to pull base image"
        log_ok "Base image cached on device"
    else
        log "L4T JetPack base image already cached"
    fi

    # Sync app code
    log "Syncing inference app to device..."
    rsync -az --delete -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q" \
        "$SCRIPT_DIR/inference/" "root@${DEVICE}:/tmp/inference-build/"

    # Build on device
    log "Building inference on device..."
    ssh_cmd "
        cd /tmp/inference-build
        docker build -t '$image' .
        rm -rf /tmp/inference-build
        docker stop '$container' 2>/dev/null || true
        docker rm '$container' 2>/dev/null || true
    " || die "Inference build failed"
    log_ok "inference"
}

deploy_inference

# Start containers
log "Starting containers..."

ssh_cmd "docker run -d --name sandbox-go2rtc --restart unless-stopped \
    --network squirrel-net -p 8554:8554 -p 1984:1984 \
    sandbox/squirrel-go2rtc:dev >/dev/null 2>&1" || true

ssh_cmd "docker run -d --name sandbox-inference --restart unless-stopped \
    --network squirrel-net --runtime nvidia -p 8555:8555 \
    -v /data/sandbox/squirrel-cam/models:/models \
    -v /tmp/squirrel-sock:/tmp \
    -e SOURCE_URI=rtsp://sandbox-go2rtc:8554/test \
    sandbox/squirrel-inference:dev >/dev/null 2>&1" || true

ssh_cmd "docker run -d --name sandbox-squirrel-app --restart unless-stopped \
    --network squirrel-net \
    -v /tmp/squirrel-sock:/tmp \
    sandbox/squirrel-app:dev >/dev/null 2>&1" || true

log_ok "All containers started"

log ""
log "Streams:"
log "  Raw:       rtsp://$DEVICE:8554/test"
log "  go2rtc UI: http://$DEVICE:1984"
log ""
log "Logs:"
log "  ssh root@$DEVICE 'docker logs -f sandbox-inference'"
