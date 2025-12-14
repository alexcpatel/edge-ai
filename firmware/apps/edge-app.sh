#!/bin/bash
# edge-app: Build, sign, push, and deploy containers to Edge AI devices
#
# Commands:
#   build <app>                    Build container locally
#   push <app> [version]           Push to ECR and sign
#   deploy <app> <device> [ver]    Deploy signed container to device
#   sandbox <app> <device>         Deploy as sandbox (unsigned, for dev)
#   logs <app> <device>            View container logs
#   stop <app> <device>            Stop container on device
#   list                           List available apps
#
# Examples:
#   edge-app build animal-detector
#   edge-app push animal-detector v1
#   edge-app deploy animal-detector 192.168.1.100 v1
#   edge-app sandbox animal-detector edge-ai.local

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

KMS_KEY_ALIAS="alias/edge-container-signing"
# cosign v2.x required for compatibility with device (v3.x uses incompatible OCI referrers)
COSIGN_BIN="${COSIGN_BIN:-cosign-v2}"

cmd_build() {
    local app="${1:-}"
    [ -z "$app" ] && die "Usage: edge-app build <app-name>"

    local app_dir="$APPS_DIR/$app"
    [ -d "$app_dir" ] || die "App not found: $app_dir"

    log "Building $app for linux/arm64..."
    docker buildx build --platform linux/arm64 -t "$app:local" --load "$app_dir"
    log "Built: $app:local"
}

cmd_push() {
    local app="${1:-}"
    local version="${2:-latest}"
    [ -z "$app" ] && die "Usage: edge-app push <app-name> [version]"

    local app_dir="$APPS_DIR/$app"
    [ -d "$app_dir" ] || die "App not found: $app_dir"

    # Build if not already built
    if ! docker image inspect "$app:local" >/dev/null 2>&1; then
        cmd_build "$app"
    fi

    ecr_login

    local ecr_tag
    ecr_tag=$(get_app_image_tag "$app" "$version")

    log "Tagging: $app:local -> $ecr_tag"
    docker tag "$app:local" "$ecr_tag"

    log "Pushing to ECR..."
    docker push "$ecr_tag"

    log "Signing with KMS..."
    export AWS_REGION
    if "$COSIGN_BIN" sign --yes --key "awskms:///${KMS_KEY_ALIAS}" "$ecr_tag" 2>&1; then
        log "Signed successfully"
    else
        # Check if signature already exists (immutable tag error is OK)
        if "$COSIGN_BIN" verify --key "awskms:///${KMS_KEY_ALIAS}" "$ecr_tag" >/dev/null 2>&1; then
            log "Signature already exists for this digest"
        else
            die "Signing failed"
        fi
    fi

    log "Done! Signed image: $ecr_tag"
}

cmd_deploy() {
    local app="${1:-}"
    local device="${2:-}"
    local version="${3:-latest}"

    [ -z "$app" ] || [ -z "$device" ] && die "Usage: edge-app deploy <app-name> <device> [version]"

    check_device "$device"

    local ecr_tag
    ecr_tag=$(get_app_image_tag "$app" "$version")

    log "Deploying $app ($version) to $device..."

    # Get ECR login for device
    local ecr_url
    ecr_url=$(get_ecr_url)
    local registry="${ecr_url%%/*}"
    local ecr_password
    ecr_password=$(aws ecr get-login-password --region "$AWS_REGION")

    ssh_device "$device" "
        set -euo pipefail

        # Use writable location for Docker config (rootfs is read-only)
        export DOCKER_CONFIG=/data/.docker
        mkdir -p \$DOCKER_CONFIG

        # Login to ECR
        echo '$ecr_password' | docker login --username AWS --password-stdin '$registry'

        # Pull with signature verification
        edge-docker pull '$ecr_tag'

        # Stop existing container if running
        docker stop '$app' 2>/dev/null || true
        docker rm '$app' 2>/dev/null || true

        # Create app data directory
        mkdir -p /data/apps/$app

        # Run container
        docker run -d \\
            --name '$app' \\
            --restart unless-stopped \\
            -v /data/apps/$app:/data \\
            '$ecr_tag'

        echo 'Container started'
    "

    log "Deployed $app to $device"
}

cmd_sandbox() {
    local app="${1:-}"
    local device="${2:-}"

    [ -z "$app" ] || [ -z "$device" ] && die "Usage: edge-app sandbox <app-name> <device>"

    local app_dir="$APPS_DIR/$app"
    [ -d "$app_dir" ] || die "App not found: $app_dir"

    check_device "$device"

    log "Deploying $app as sandbox to $device..."

    # Build locally for ARM64
    docker buildx build --platform linux/arm64 -t "sandbox/$app:dev" --load "$app_dir"

    # Save and transfer
    local tarball="/tmp/${app}-sandbox.tar.gz"
    docker save "sandbox/$app:dev" | gzip > "$tarball"

    log "Transferring to device..."
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$tarball" "root@${device}:/tmp/"

    ssh_device "$device" "
        set -euo pipefail

        # Load image
        docker load < '/tmp/${app}-sandbox.tar.gz'
        rm -f '/tmp/${app}-sandbox.tar.gz'

        # Stop existing container if running
        docker stop 'sandbox-$app' 2>/dev/null || true
        docker rm 'sandbox-$app' 2>/dev/null || true

        # Create sandbox directory
        mkdir -p /data/sandbox/$app

        # Run as sandbox (mounts /data/sandbox for live editing)
        docker run -d \\
            --name 'sandbox-$app' \\
            --restart unless-stopped \\
            -v /data/sandbox/$app:/data \\
            'sandbox/$app:dev'

        echo 'Sandbox container started'
        echo 'Edit files in /data/sandbox/$app on device for live changes'
    "

    rm -f "$tarball"
    log "Sandbox deployed. SSH to device and edit /data/sandbox/$app"
}

cmd_logs() {
    local app="${1:-}"
    local device="${2:-}"
    local follow="${3:-}"

    [ -z "$app" ] || [ -z "$device" ] && die "Usage: edge-app logs <app-name> <device> [-f]"

    check_device "$device"

    local docker_args="logs"
    [ "$follow" = "-f" ] && docker_args="logs -f"

    ssh_device "$device" "docker $docker_args '$app' 2>/dev/null || docker $docker_args 'sandbox-$app'"
}

cmd_stop() {
    local app="${1:-}"
    local device="${2:-}"

    [ -z "$app" ] || [ -z "$device" ] && die "Usage: edge-app stop <app-name> <device>"

    check_device "$device"

    log "Stopping $app on $device..."
    ssh_device "$device" "
        docker stop '$app' 2>/dev/null || docker stop 'sandbox-$app' 2>/dev/null || true
        docker rm '$app' 2>/dev/null || docker rm 'sandbox-$app' 2>/dev/null || true
    "
    log "Stopped"
}

cmd_remove() {
    local app="${1:-}"
    local device="${2:-}"

    [ -z "$app" ] || [ -z "$device" ] && die "Usage: edge-app remove <app-name> <device>"

    check_device "$device"

    log "Removing $app from $device..."
    ssh_device "$device" "
        # Stop and remove containers
        docker stop '$app' 2>/dev/null || true
        docker stop 'sandbox-$app' 2>/dev/null || true
        docker rm '$app' 2>/dev/null || true
        docker rm 'sandbox-$app' 2>/dev/null || true

        # Remove app data
        rm -rf /data/apps/$app
        rm -rf /data/sandbox/$app

        echo 'Removed container and data'
    "
    log "Removed $app"
}

cmd_list() {
    log "Available apps:"
    for app in "$APPS_DIR"/*/; do
        [ -d "$app" ] || continue
        local name=$(basename "$app")
        [ "$name" = "scripts" ] && continue
        echo "  - $name"
    done
}

show_help() {
    cat <<'EOF'
edge-app: Build, sign, push, and deploy containers to Edge AI devices

Commands:
  build <app>                    Build container locally
  push <app> [version]           Push to ECR and sign (requires AWS creds)
  deploy <app> <device> [ver]    Deploy signed container from ECR to device
  sandbox <app> <device>         Deploy as sandbox (unsigned, for development)
  logs <app> <device> [-f]       View container logs
  stop <app> <device>            Stop container on device
  remove <app> <device>          Remove container and data from device
  list                           List available apps

Workflow:
  # Production: build → sign → deploy
  edge-app build animal-detector
  edge-app push animal-detector v1
  edge-app deploy animal-detector mydevice.local v1

  # Development: sandbox (no signing required)
  edge-app sandbox animal-detector mydevice.local
  # Then SSH to device and edit /data/sandbox/animal-detector/

Environment:
  AWS_REGION    AWS region (default: us-east-2)
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        build)   cmd_build "$@" ;;
        push)    cmd_push "$@" ;;
        deploy)  cmd_deploy "$@" ;;
        sandbox) cmd_sandbox "$@" ;;
        logs)    cmd_logs "$@" ;;
        stop)    cmd_stop "$@" ;;
        remove)  cmd_remove "$@" ;;
        list)    cmd_list ;;
        help|--help|-h) show_help ;;
        *) die "Unknown command: $cmd. Use 'edge-app help' for usage." ;;
    esac
}

main "$@"

