#!/bin/bash
# Deploy squirrel-cam ML pipeline to device
#
# Usage: ./deploy.sh <device>
#
# Deploys 3 containers:
#   - go2rtc:    RTSP proxy for Blink cameras
#   - deepstream: GPU inference with YOLOv8
#   - app:       Detection event handler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()      { echo "[squirrel-cam] $*"; }
log_ok()   { echo "[squirrel-cam] ✓ $*"; }
log_skip() { echo "[squirrel-cam] ○ $* (unchanged)"; }
die()      { echo "[squirrel-cam] ERROR: $*" >&2; exit 1; }

DEVICE="${1:-}"
[ -z "$DEVICE" ] && die "Usage: $0 <device-ip-or-hostname>"

ssh_cmd() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
        "root@${DEVICE}" "$@"
}

log "Checking device connectivity..."
if ! ssh_cmd "echo ok" >/dev/null 2>&1; then
    die "Cannot reach device: $DEVICE"
fi
log_ok "Device reachable"

ssh_cmd "
    mkdir -p /data/sandbox/squirrel-cam/clips
    mkdir -p /data/sandbox/squirrel-cam/models
    docker network create squirrel-net 2>/dev/null || true
"

deploy_container() {
    local name="$1"
    local build_dir="$2"
    local image_name="sandbox/$name:dev"
    local container_name="sandbox-$name"

    log "Building $name..."
    docker buildx build --platform linux/arm64 -t "$image_name" --load "$build_dir" -q >/dev/null
    local local_id
    local_id=$(docker images -q "$image_name")

    local remote_id
    remote_id=$(ssh_cmd "docker inspect --format='{{.Image}}' '$container_name' 2>/dev/null | cut -c8-19" || echo "")

    if [ -n "$remote_id" ]; then
        local local_short="${local_id:0:12}"
        if [ "$local_short" = "$remote_id" ]; then
            log_skip "$name"
            return 1
        fi
    fi

    log "Deploying $name..."
    local tarball="/tmp/${name}-sandbox.tar.gz"
    docker save "$image_name" | gzip > "$tarball"

    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
        "$tarball" "root@${DEVICE}:/tmp/"

    ssh_cmd "
        docker load < '/tmp/${name}-sandbox.tar.gz' >/dev/null
        rm -f '/tmp/${name}-sandbox.tar.gz'
        docker stop '$container_name' 2>/dev/null || true
        docker rm '$container_name' 2>/dev/null || true
    "

    rm -f "$tarball"
    log_ok "$name deployed"
    return 0
}

check_nvidia_runtime() {
    # Verify nvidia-container-toolkit is available
    log "Checking NVIDIA container runtime..."
    if ! ssh_cmd "docker info 2>/dev/null | grep -q nvidia"; then
        die "nvidia-container-toolkit not installed. Rebuild Yocto image with nvidia-container-toolkit package."
    fi
    log_ok "NVIDIA runtime available"
}

deploy_deepstream() {
    # DeepStream must be built ON the Jetson (L4T images are Jetson-only)
    local image_name="sandbox/squirrel-deepstream:dev"
    local container_name="sandbox-deepstream"
    local cache_file="/data/docker-cache/squirrel-deepstream.tar"

    # Verify nvidia runtime is available
    check_nvidia_runtime

    # Compute hash of source files to detect changes
    local src_hash=$(tar cf - -C "$SCRIPT_DIR/deepstream" . 2>/dev/null | md5 -q)

    log "Syncing deepstream source to device..."
    rsync -az --delete -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
        "$SCRIPT_DIR/deepstream/" "root@${DEVICE}:/tmp/deepstream-build/"

    log "Building deepstream on device..."
    ssh_cmd "
        set -e
        export DOCKER_CONFIG=/data/.docker
        mkdir -p \$DOCKER_CONFIG /data/docker-cache

        # Check if we have a cached image with matching hash
        if [ -f '$cache_file' ] && [ -f '${cache_file}.hash' ]; then
            cached_hash=\$(cat '${cache_file}.hash')
            if [ \"\$cached_hash\" = '$src_hash' ]; then
                echo 'Loading cached image (source unchanged)...'
                docker load < '$cache_file'
                docker stop '$container_name' 2>/dev/null || true
                docker rm '$container_name' 2>/dev/null || true
                exit 0
            fi
        fi

        echo 'Building image (this takes ~10min first time, cached after)...'
        cd /tmp/deepstream-build
        docker build -t '$image_name' .
        rm -rf /tmp/deepstream-build

        # Cache the built image for next time
        echo 'Caching built image...'
        docker save '$image_name' > '$cache_file'
        echo '$src_hash' > '${cache_file}.hash'

        docker stop '$container_name' 2>/dev/null || true
        docker rm '$container_name' 2>/dev/null || true
    " || die "DeepStream build failed on device"
    log_ok "deepstream ready"
}

setup_blink_auth() {
    local creds_file="/data/sandbox/squirrel-cam/credentials.json"

    if ssh_cmd "test -f '$creds_file' && grep -q token '$creds_file'" 2>/dev/null; then
        log_ok "Blink already authenticated"
        return 0
    fi

    log ""
    log "Blink authentication required"
    read -p "Blink email: " blink_email
    [ -z "$blink_email" ] && die "Email required"

    read -s -p "Blink password: " blink_password
    echo ""
    [ -z "$blink_password" ] && die "Password required"

    log "Authenticating (2FA code will be sent)..."

    ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "root@${DEVICE}" \
        "docker run --rm -it -v /data/sandbox/squirrel-cam:/data sandbox/squirrel-app:dev \
         python3 /app/auth.py '$blink_email' '$blink_password'"

    if ssh_cmd "test -f '$creds_file' && grep -q token '$creds_file'" 2>/dev/null; then
        log_ok "Blink authentication successful"
    else
        die "Authentication failed"
    fi
}

start_go2rtc() {
    local container="sandbox-go2rtc"
    local image="sandbox/squirrel-go2rtc:dev"

    if ssh_cmd "docker ps --format '{{.Names}}' | grep -q '^${container}$'" 2>/dev/null; then
        log_ok "go2rtc already running"
        return 0
    fi

    log "Starting go2rtc..."
    ssh_cmd "docker run -d \
        --name '$container' \
        --restart unless-stopped \
        --network squirrel-net \
        -p 8554:8554 \
        -p 1984:1984 \
        '$image' >/dev/null"
    log_ok "go2rtc started"
}

start_deepstream() {
    local container="sandbox-deepstream"
    local image="sandbox/squirrel-deepstream:dev"

    if ssh_cmd "docker ps --format '{{.Names}}' | grep -q '^${container}$'" 2>/dev/null; then
        log_ok "deepstream already running"
        return 0
    fi

    log "Starting deepstream..."
    ssh_cmd "docker run -d \
        --name '$container' \
        --restart unless-stopped \
        --network squirrel-net \
        --runtime nvidia \
        -p 8555:8555 \
        -v /data/sandbox/squirrel-cam/models:/models \
        -v /tmp/squirrel-sock:/tmp \
        -e SOURCE_URI=rtsp://sandbox-go2rtc:8554/test \
        -e RTSP_PORT=8555 \
        '$image' >/dev/null"
    log_ok "deepstream started"
}

start_app() {
    local container="sandbox-squirrel-app"
    local image="sandbox/squirrel-app:dev"

    if ssh_cmd "docker ps --format '{{.Names}}' | grep -q '^${container}$'" 2>/dev/null; then
        log_ok "app already running"
        return 0
    fi

    log "Starting app..."
    ssh_cmd "docker run -d \
        --name '$container' \
        --restart unless-stopped \
        --network squirrel-net \
        -v /tmp/squirrel-sock:/tmp \
        -e SOCKET_PATH=/tmp/detections.sock \
        '$image' >/dev/null"
    log_ok "app started"
}

stop_all() {
    log "Stopping containers..."
    ssh_cmd "
        docker stop sandbox-squirrel-app sandbox-deepstream sandbox-go2rtc 2>/dev/null || true
        docker rm sandbox-squirrel-app sandbox-deepstream sandbox-go2rtc 2>/dev/null || true
    "
}

# Handle stop command
if [ "${1:-}" = "stop" ]; then
    DEVICE="${2:-}"
    [ -z "$DEVICE" ] && die "Usage: $0 stop <device>"
    stop_all
    exit 0
fi

# Deploy containers
deploy_container "squirrel-go2rtc" "$SCRIPT_DIR/go2rtc"
deploy_deepstream  # Built on device (L4T images are Jetson-only)
deploy_container "squirrel-app" "$SCRIPT_DIR"

# Auth
setup_blink_auth

# Start containers (order matters: go2rtc -> deepstream -> app)
start_go2rtc
start_deepstream
start_app

# Status
log ""
log "=== Status ==="
ssh_cmd "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null || true
log ""
log "=== View Streams ==="
log "  Raw feed:       vlc rtsp://$DEVICE:8554/test"
log "  Detection feed: vlc rtsp://$DEVICE:8555/ds"
log "  go2rtc UI:      http://$DEVICE:1984"
log ""
log "=== Logs ==="
log "  App:        ssh root@$DEVICE 'docker logs -f sandbox-squirrel-app'"
log "  DeepStream: ssh root@$DEVICE 'docker logs -f sandbox-deepstream'"
