#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EC2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$EC2_DIR/config/aws-config.sh"
source "$REPO_ROOT/firmware/yocto/config/yocto-config.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info() { echo -e "${YELLOW}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_error() { echo -e "${RED}$*${NC}"; }

check_aws_creds() {
    aws sts get-caller-identity >/dev/null 2>&1 || { log_error "AWS credentials not configured"; exit 1; }
}

INSTANCE_CACHE_DIR="${HOME}/.ssh/ec2-instance-cache"
CACHE_MAX_AGE=300

get_instance_id() {
    local cache_file="${INSTANCE_CACHE_DIR}/instance_id"
    local cache_time="${INSTANCE_CACHE_DIR}/instance_id.time"
    mkdir -p "$INSTANCE_CACHE_DIR" && chmod 700 "$INSTANCE_CACHE_DIR"

    if [ -f "$cache_file" ] && [ -f "$cache_time" ]; then
        local age=$(($(date +%s) - $(cat "$cache_time" 2>/dev/null || echo 0)))
        if [ $age -lt $CACHE_MAX_AGE ]; then
            local cached=$(cat "$cache_file" 2>/dev/null || echo "")
            [ -n "$cached" ] && [ "$cached" != "None" ] && { echo "$cached"; return 0; }
        fi
    fi

    local id=$(aws ec2 describe-instances --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$EC2_INSTANCE_NAME" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "")

    [ -n "$id" ] && [ "$id" != "None" ] && { echo "$id" > "$cache_file"; date +%s > "$cache_time"; }
    echo "$id"
}

get_instance_or_exit() {
    local id=$(get_instance_id)
    [ -z "$id" ] || [ "$id" == "None" ] && { log_error "Instance '$EC2_INSTANCE_NAME' not found"; exit 1; }
    echo "$id"
}

get_instance_ip() {
    aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$1" \
        --query "Reservations[0].Instances[0].PublicIpAddress" --output text 2>/dev/null || echo ""
}

get_instance_state() {
    [ -z "$1" ] || [ "$1" == "None" ] && { echo "not-found"; return; }
    aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$1" \
        --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null || echo "unknown"
}

get_instance_ip_or_exit() {
    local id=$(get_instance_id)
    [ -z "$id" ] || [ "$id" == "None" ] && { log_error "Instance not found"; exit 1; }
    local ip=$(get_instance_ip "$id")
    [ -z "$ip" ] || [ "$ip" == "None" ] && { log_error "Instance not running"; exit 1; }
    echo "$ip"
}

SSH_KEY="${SSH_KEY:-$HOME/.ssh/yocto-builder-keypair.pem}"

ssh_cmd() {
    local ip="$1"; shift
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${EC2_USER}@${ip}" "$@"
}

rsync_cmd() {
    local ip="$1"; shift
    rsync -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR" "$@"
}
