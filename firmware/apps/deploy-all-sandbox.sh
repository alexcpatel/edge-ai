#!/bin/bash
# Deploy all app containers as sandbox to device
#
# Usage: ./deploy-all-sandbox.sh <device>
# Example: ./deploy-all-sandbox.sh 192.168.86.34
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
        docker run -d \
            --name '$container_name' \
            --restart unless-stopped \
            -v /data/sandbox/$app:/data \
            '$image_name' >/dev/null
    "

    rm -f "$tarball"
    log_ok "$app deployed"
}

setup_blink_credentials() {
    local creds_file="/data/sandbox/squirrel-cam/credentials.json"
    local code_file="/data/sandbox/squirrel-cam/2fa_code.txt"

    # Check if already authenticated (has token)
    if ssh_cmd "test -f '$creds_file' && grep -q token '$creds_file'" 2>/dev/null; then
        log_ok "Blink already authenticated"
        return 0
    fi

    # Stop container to prevent auth loops
    ssh_cmd "docker stop sandbox-squirrel-cam 2>/dev/null || true"

    # Prompt for credentials if needed
    if ! ssh_cmd "test -f '$creds_file'" 2>/dev/null; then
        log ""
        log "Blink credentials required"
        read -p "Blink email: " blink_email
        [ -z "$blink_email" ] && die "Email required"

        read -s -p "Blink password: " blink_password
        echo ""

        [ -z "$blink_password" ] && die "Password required"

        ssh_cmd "cat > '$creds_file'" << EOF
{"username": "$blink_email", "password": "$blink_password"}
EOF
        log_ok "Credentials saved"
    fi

    # Prompt for 2FA code upfront (Blink always requires it for new logins)
    log ""
    log "Blink will send a 2FA code to your email/SMS when we start."
    read -p "Press Enter to continue, then enter the code: "

    # Start container - it will trigger 2FA
    ssh_cmd "docker start sandbox-squirrel-cam"
    log "Waiting for 2FA code to be sent..."
    sleep 5

    # Get the 2FA code
    read -p "Enter 2FA code from email/SMS: " twofa_code
    [ -z "$twofa_code" ] && die "2FA code required"

    # Write code and wait for verification
    ssh_cmd "echo '$twofa_code' > '$code_file'"
    log "Verifying..."
    sleep 8

    # Check result
    local logs
    logs=$(ssh_cmd "docker logs --tail 15 sandbox-squirrel-cam 2>&1" || echo "")

    if echo "$logs" | grep -q "2FA verification successful\|Connected to Blink\|Found.*cameras"; then
        log_ok "Blink authentication successful!"
    else
        log "Authentication may have failed. Check logs:"
        log "  ssh root@$DEVICE 'docker logs sandbox-squirrel-cam'"
    fi
}

# Deploy apps
deploy_app squirrel-cam

# Setup Blink credentials
setup_blink_credentials

# Show status
log ""
log "=== Status ==="
ssh_cmd "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null || true
log ""
log "Logs: ssh root@$DEVICE 'docker logs -f sandbox-squirrel-cam'"
