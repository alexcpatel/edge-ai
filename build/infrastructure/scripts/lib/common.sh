#!/bin/bash
# Common functions and configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$INFRA_DIR/config/aws-config.sh"
source "$INFRA_DIR/../yocto/config/yocto-config.sh"

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
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$EC2_INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null || echo ""
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
    ssh -i "$EC2_SSH_KEY_PATH" -o StrictHostKeyChecking=no "${EC2_USER}@${ip}" "$@"
}

