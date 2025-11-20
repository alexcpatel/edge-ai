#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Monitor build session and stop instance when build ends (if flag is set)
# This script runs on the EC2 instance

SESSION_NAME="yocto-build"
FLAG_FILE="/tmp/auto-stop-instance"
INSTANCE_ID_FILE="/tmp/instance-id"

# Get instance ID from metadata service
get_instance_id() {
    if [ -f "$INSTANCE_ID_FILE" ]; then
        cat "$INSTANCE_ID_FILE"
    else
        # Get from EC2 metadata service
        instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
        if [ -n "$instance_id" ]; then
            echo "$instance_id" > "$INSTANCE_ID_FILE"
            echo "$instance_id"
        else
            echo ""
        fi
    fi
}

# Stop the instance
stop_instance() {
    local instance_id="$1"

    log_info "Build ended. Stopping instance $instance_id..."

    # Get region from metadata service
    local region
    region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "")

    if [ -z "$region" ]; then
        log_error "Could not determine AWS region. Instance will not be stopped automatically."
        return 1
    fi

    # Use AWS CLI with instance profile (IAM role attached to EC2 instance)
    aws ec2 stop-instances --region "$region" --instance-ids "$instance_id" || {
        log_error "Failed to stop instance. Check IAM permissions."
        return 1
    }
    log_success "Instance stop initiated"
}

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

# Main monitoring loop
main() {
    log_info "Starting build monitor (will stop instance when build ends if flag is set)"

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
    POST_BUILD_SCRIPT="/home/ubuntu/edge-ai/build/remote/scripts/post-build-image.sh"
    
    if [ -f "$LOG_FILE" ]; then
        # Check if build succeeded (look for "Tasks Summary" with "all succeeded")
        if grep -q "Tasks Summary:.*all succeeded" "$LOG_FILE" 2>/dev/null; then
            log_info "Build succeeded! Recording timestamp..."
            date +%s > "$SUCCESS_FILE" 2>/dev/null || true
            
            # Run post-build script to create SD card image
            if [ -f "$POST_BUILD_SCRIPT" ]; then
                log_info "Running post-build script to create SD card image..."
                bash "$POST_BUILD_SCRIPT" || {
                    log_error "Post-build script failed, but build succeeded"
                }
            fi
        fi
    fi
    
    # Check if auto-stop flag is set
    if [ -f "$FLAG_FILE" ]; then
        log_info "Auto-stop flag found, stopping instance..."
        instance_id=$(get_instance_id)
        if [ -n "$instance_id" ]; then
            stop_instance "$instance_id"
        else
            log_error "Could not determine instance ID"
        fi
        rm -f "$FLAG_FILE"
    fi
}

main "$@"

