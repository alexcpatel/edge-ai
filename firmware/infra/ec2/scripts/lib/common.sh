#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Common functions and configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EC2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$EC2_DIR/config/aws-config.sh"
source "$REPO_ROOT/firmware/yocto/config/yocto-config.sh"

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

# Cache directory for instance metadata
INSTANCE_CACHE_DIR="${HOME}/.ssh/ec2-instance-cache"

get_instance_id() {
    # Cache instance ID to avoid redundant AWS API calls
    local cache_file="${INSTANCE_CACHE_DIR}/instance_id"
    local cache_time_file="${INSTANCE_CACHE_DIR}/instance_id.time"
    local cache_max_age=300  # Cache for 5 minutes

    mkdir -p "$INSTANCE_CACHE_DIR"
    chmod 700 "$INSTANCE_CACHE_DIR"

    # Check if we have a cached instance ID that's still valid
    if [ -f "$cache_file" ] && [ -f "$cache_time_file" ]; then
        local cache_timestamp
        cache_timestamp=$(cat "$cache_time_file" 2>/dev/null || echo "0")
        local current_timestamp
        current_timestamp=$(date +%s)
        local cache_age=$((current_timestamp - cache_timestamp))

        if [ $cache_age -lt $cache_max_age ]; then
            local cached_id
            cached_id=$(cat "$cache_file" 2>/dev/null || echo "")
            if [ -n "$cached_id" ] && [ "$cached_id" != "None" ]; then
                echo "$cached_id"
                return 0
            fi
        fi
    fi

    # Get instance ID, excluding terminated instances
    # Prefer running instances, but return any non-terminated instance
    local instance_id
    instance_id=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$EC2_INSTANCE_NAME" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null || echo "")

    # Cache the result
    if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
        echo "$instance_id" > "$cache_file"
        echo "$(date +%s)" > "$cache_time_file"
    fi

    echo "$instance_id"
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

rsync_cmd() {
    local ip="$1"
    shift

    # Always use EC2 Instance Connect for rsync authentication
    source "$(dirname "${BASH_SOURCE[0]}")/ec2-instance-connect.sh"
    local instance_id
    instance_id=$(get_instance_id)
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        log_error "Instance not found"
        exit 1
    fi

    # Get cached or new temporary key
    local temp_key
    if ! temp_key=$(setup_temp_ssh_key "$instance_id") || [ -z "$temp_key" ]; then
        log_error "Failed to send SSH public key via EC2 Instance Connect"
        return 1
    fi

    # Use temporary key for rsync
    rsync -e "ssh -i $temp_key -o StrictHostKeyChecking=no" "$@"
}

yocto_cmd() {
    local ip="$1"
    shift
    ssh_cmd "$ip" "cd $YOCTO_DIR && source poky/oe-init-build-env build && $*"
}

