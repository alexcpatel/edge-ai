#!/bin/bash
# Common utilities for edge-ai app management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
APPS_DIR="$REPO_ROOT/firmware/apps"

AWS_REGION="${AWS_REGION:-us-east-2}"

log()     { echo "[edge-app] $*"; }
log_err() { echo "[edge-app] ERROR: $*" >&2; }
die()     { log_err "$*"; exit 1; }

get_ecr_url() {
    aws ssm get-parameter \
        --name "/edge-ai/ecr/repository-url" \
        --region "$AWS_REGION" \
        --query "Parameter.Value" \
        --output text
}

ecr_login() {
    local ecr_url
    ecr_url=$(get_ecr_url)
    local registry="${ecr_url%%/*}"

    log "Logging into ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$registry" >/dev/null
}

ssh_device() {
    local device="$1"
    shift
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@${device}" "$@"
}

check_device() {
    local device="$1"
    if ! ssh_device "$device" "echo ok" >/dev/null 2>&1; then
        die "Cannot reach device: $device"
    fi
}

get_app_image_tag() {
    local app="$1"
    local version="${2:-latest}"
    local ecr_url
    ecr_url=$(get_ecr_url)
    echo "${ecr_url}:${app}-${version}"
}
