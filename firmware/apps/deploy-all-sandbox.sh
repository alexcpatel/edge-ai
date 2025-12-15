#!/bin/bash
# Deploy all app containers to device
#
# Usage: ./deploy-all-sandbox.sh <device>
#
# Idempotent - skips unchanged containers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR"

log()      { echo "[deploy-all-sandbox] $*"; }
log_ok()   { echo "[deploy-all-sandbox] ✓ $*"; }
log_skip() { echo "[deploy-all-sandbox] ○ $* (unchanged)"; }
die()      { echo "[deploy-all-sandbox] ERROR: $*" >&2; exit 1; }

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

# Create directories
ssh_cmd "mkdir -p /data/sandbox/squirrel-cam/clips"

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

    rm -f "$tarball"
    log_ok "$app image deployed"
}

setup_blink_auth() {
    local creds_file="/data/sandbox/squirrel-cam/credentials.json"

    # Check if already authenticated
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

    log "Authenticating (2FA code will be sent to your email/SMS)..."
    log ""

    # Run auth.py interactively - blinkpy will prompt for 2FA only
    ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "root@${DEVICE}" \
        "docker run --rm -it -v /data/sandbox/squirrel-cam:/data sandbox/squirrel-cam:dev \
         python3 /app/auth.py '$blink_email' '$blink_password'"

    # Verify it worked
    if ssh_cmd "test -f '$creds_file' && grep -q token '$creds_file'" 2>/dev/null; then
        log_ok "Blink authentication successful"
    else
        die "Authentication failed"
    fi
}

start_container() {
    local container_name="sandbox-squirrel-cam"
    local image_name="sandbox/squirrel-cam:dev"

    # Start if not running
    if ssh_cmd "docker ps --format '{{.Names}}' | grep -q '^${container_name}$'" 2>/dev/null; then
        log_ok "Container already running"
    else
        ssh_cmd "docker run -d \
            --name '$container_name' \
            --restart unless-stopped \
            -v /data/sandbox/squirrel-cam:/data \
            '$image_name' >/dev/null"
        log_ok "Container started"
    fi
}

# Deploy
deploy_app squirrel-cam

# Auth (if needed)
setup_blink_auth

# Start container
start_container

# Status
log ""
log "=== Status ==="
ssh_cmd "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null || true
log ""
log "Logs: ssh root@$DEVICE 'docker logs -f sandbox-squirrel-cam'"
