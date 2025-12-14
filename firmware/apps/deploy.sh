#!/bin/bash
# Deploy all app containers to device
#
# Usage: ./deploy.sh <device>
# Example: ./deploy.sh 192.168.86.34
#
# Deploys:
#   - homeassistant (Blink camera integration)
#   - squirrel-cam (AI detection)
#
# Idempotent - skips unchanged containers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR"
EDGE_APP="$APPS_DIR/edge-app.sh"

log()     { echo "[deploy] $*"; }
log_ok()  { echo "[deploy] ✓ $*"; }
log_skip() { echo "[deploy] ○ $* (unchanged)"; }
die()     { echo "[deploy] ERROR: $*" >&2; exit 1; }

DEVICE="${1:-}"
[ -z "$DEVICE" ] && die "Usage: $0 <device-ip-or-hostname>"

ssh_cmd() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
        "root@${DEVICE}" "$@"
}

# Check device is reachable
log "Checking device connectivity..."
if ! ssh_cmd "echo ok" >/dev/null 2>&1; then
    die "Cannot reach device: $DEVICE"
fi
log_ok "Device reachable"

# Create shared directories (idempotent via mkdir -p)
ssh_cmd "mkdir -p /data/shared/clips /data/sandbox/homeassistant /data/sandbox/squirrel-cam"

deploy_app() {
    local app="$1"
    local app_dir="$APPS_DIR/$app"
    local container_name="sandbox-$app"
    local image_name="sandbox/$app:dev"

    # Build locally and get image ID
    log "Building $app..."
    docker buildx build --platform linux/arm64 -t "$image_name" --load "$app_dir" -q >/dev/null
    local local_id
    local_id=$(docker images -q "$image_name")

    # Get running container's image ID on device
    local remote_id
    remote_id=$(ssh_cmd "docker inspect --format='{{.Image}}' '$container_name' 2>/dev/null | cut -c8-19" || echo "")

    # Check if we need to deploy
    if [ -n "$remote_id" ]; then
        # Compare first 12 chars of image ID
        local local_short="${local_id:0:12}"
        if [ "$local_short" = "$remote_id" ]; then
            log_skip "$app"
            return 0
        fi
    fi

    # Transfer and deploy
    log "Deploying $app..."
    local tarball="/tmp/${app}-sandbox.tar.gz"
    docker save "$image_name" | gzip > "$tarball"

    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
        "$tarball" "root@${DEVICE}:/tmp/"

    ssh_cmd "
        docker load < '/tmp/${app}-sandbox.tar.gz' >/dev/null
        rm -f '/tmp/${app}-sandbox.tar.gz'
        docker stop '$container_name' 2>/dev/null || true
        docker rm '$container_name' 2>/dev/null || true
    "

    # Get docker run args from sandbox.json if present
    local extra_args=""
    local sandbox_config="$app_dir/sandbox.json"
    if [ -f "$sandbox_config" ]; then
        extra_args=$(python3 -c "
import json
with open('$sandbox_config') as f:
    cfg = json.load(f)
print(' '.join(cfg.get('docker_args', [])))
" 2>/dev/null || echo "")
    fi

    # Determine mount path
    local container_mount="/data"
    if echo "$extra_args" | grep -q -- "--privileged"; then
        container_mount="/config"
    fi

    ssh_cmd "
        docker run -d \
            --name '$container_name' \
            --restart unless-stopped \
            -v /data/sandbox/$app:$container_mount \
            $extra_args \
            '$image_name' >/dev/null
    "

    rm -f "$tarball"
    log_ok "$app deployed"
}

# Deploy apps
deploy_app homeassistant
deploy_app squirrel-cam

# Show status
log ""
log "=== Status ==="
ssh_cmd "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null || true
log ""
log "Home Assistant: http://${DEVICE}:8123"
