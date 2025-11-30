#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Monitor build session and stop EC2 when build ends (if flag is set)
# This script runs on the EC2 instance

SESSION_NAME="yocto-build"
FLAG_FILE="/tmp/auto-stop-ec2"
EC2_ID_FILE="/tmp/ec2-instance-id"

# Get EC2 instance ID from metadata service
get_ec2_id() {
    if [ -f "$EC2_ID_FILE" ]; then
        cat "$EC2_ID_FILE"
    else
        # Get from EC2 metadata service
        ec2_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
        if [ -n "$ec2_id" ]; then
            echo "$ec2_id" > "$EC2_ID_FILE"
            echo "$ec2_id"
        else
            echo ""
        fi
    fi
}

# Stop the EC2 instance
stop_ec2() {
    local ec2_id="$1"

    log_info "Build ended. Stopping EC2 $ec2_id..."

    # Get region from metadata service
    local region
    region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "")

    if [ -z "$region" ]; then
        log_error "Could not determine AWS region. EC2 will not be stopped automatically."
        return 1
    fi

    # Use AWS CLI with instance profile (IAM role attached to EC2)
    aws ec2 stop-instances --region "$region" --instance-ids "$ec2_id" || {
        log_error "Failed to stop EC2. Check IAM permissions."
        return 1
    }
    log_success "EC2 stop initiated"
}

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

# Main monitoring loop
main() {
    log_info "Starting build monitor (will stop EC2 when build ends if flag is set)"

    # Wait for build session to start (or use existing one)
    while ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; do
        sleep 2
    done

    log_info "Build session detected, monitoring..."

    # Monitor the session
    while tmux has-session -t "$SESSION_NAME" 2>/dev/null; do
        sleep 5
    done

    # Session ended - check if build succeeded and record timestamp
    LOG_FILE="/tmp/yocto-build.log"
    SUCCESS_FILE="/home/ubuntu/yocto-tegra/.last-successful-build"

    if [ -f "$LOG_FILE" ]; then
        # Check if build succeeded (look for "Tasks Summary" with "all succeeded")
        if grep -q "Tasks Summary:.*all succeeded" "$LOG_FILE" 2>/dev/null; then
            log_info "Build succeeded! Recording timestamp..."
            date +%s > "$SUCCESS_FILE" 2>/dev/null || true
        fi
    fi

    # Check if auto-stop flag is set
    if [ -f "$FLAG_FILE" ]; then
        log_info "Auto-stop flag found, stopping EC2..."
        ec2_id=$(get_ec2_id)
        if [ -n "$ec2_id" ]; then
            stop_ec2 "$ec2_id"
        else
            log_error "Could not determine EC2 ID"
        fi
        rm -f "$FLAG_FILE"
    fi
}

main "$@"
