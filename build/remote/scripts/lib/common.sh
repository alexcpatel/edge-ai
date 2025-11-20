#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Common functions and configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REMOTE_DIR/config/aws-config.sh"
source "$REMOTE_DIR/../yocto/config/yocto-config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_error() { echo -e "${RED}$*${NC}"; }

check_aws_creds() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured"
        exit 1
    fi
}

get_instance_id() {
    # Get instance ID, excluding terminated instances
    # Prefer running instances, but return any non-terminated instance
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$EC2_INSTANCE_NAME" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null || echo ""
}

get_instance_or_exit() {
    # Get instance ID or exit with error
    local instance_id
    instance_id=$(get_instance_id)
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        log_error "Instance '$EC2_INSTANCE_NAME' not found"
        exit 1
    fi
    echo "$instance_id"
}

get_instance_ip() {
    local instance_id="$1"
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text 2>/dev/null || echo ""
}

get_instance_state() {
    local instance_id="$1"
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        echo "not-found"
        return
    fi
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text 2>/dev/null || echo "unknown"
}

ssh_cmd() {
    local ip="$1"
    shift

    # Always use EC2 Instance Connect for SSH authentication
    source "$(dirname "${BASH_SOURCE[0]}")/ec2-instance-connect.sh"
    local instance_id
    instance_id=$(get_instance_id)
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        log_error "Instance not found"
        exit 1
    fi
    ssh_cmd_ec2_connect "$ip" "$instance_id" "$@"
}

get_instance_ip_or_exit() {
    local instance_id
    instance_id=$(get_instance_id)
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        log_error "Instance not found"
        exit 1
    fi
    local ip
    ip=$(get_instance_ip "$instance_id")
    if [ -z "$ip" ] || [ "$ip" == "None" ]; then
        log_error "Instance not running"
        exit 1
    fi
    echo "$ip"
}

yocto_cmd() {
    local ip="$1"
    shift
    ssh_cmd "$ip" "cd $YOCTO_DIR && source poky/oe-init-build-env build && $*"
}

