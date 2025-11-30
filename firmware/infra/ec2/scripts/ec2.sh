#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# EC2 instance management
# Usage: ec2.sh [status|start|stop|ssh|health] [args...]

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/diagnostics.sh"

get_instance_type() {
    local instance_id="$1"
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query "Reservations[0].Instances[0].InstanceType" \
        --output text 2>/dev/null || echo ""
}

setup_ec2() {
    local ip="$1"
    local setup_script="$(dirname "${BASH_SOURCE[0]}")/on-ec2/setup.sh"

    log_info "Setting up EC2..."

    # Run setup script with environment variables
    ssh_cmd "$ip" \
        "YOCTO_BRANCH='$YOCTO_BRANCH' \
         YOCTO_MACHINE='$YOCTO_MACHINE' \
         YOCTO_DIR='$YOCTO_DIR' \
         REMOTE_SOURCE_DIR='$REMOTE_SOURCE_DIR' \
         bash -s" < "$setup_script"

    log_success "EC2 setup completed"
}

show_status() {
    check_aws_creds
    local instance_id
    instance_id=$(get_instance_id)

    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        echo "Instance: not found"
        exit 0
    fi

    local state ip instance_type
    state=$(get_instance_state "$instance_id")
    ip=$(get_instance_ip "$instance_id")
    instance_type=$(get_instance_type "$instance_id")

    echo "Instance ID: $instance_id"
    echo "Instance Type: $instance_type"
    echo "State: $state"
    [ -n "$ip" ] && [ "$ip" != "None" ] && echo "IP: $ip"

    if [ "$state" == "running" ] && [ -n "$ip" ] && [ "$ip" != "None" ]; then
        echo ""
        # Check AWS health status
        local aws_healthy=false
        local status_output
        status_output=$(aws ec2 describe-instance-status \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --include-all-instances \
            --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
            --output text 2>/dev/null || echo "")

        if [ -n "$status_output" ]; then
            local system_status instance_status
            read -r system_status instance_status <<< "$status_output"
            [ "$system_status" == "ok" ] && [ "$instance_status" == "ok" ] && aws_healthy=true
        fi

        if ! check_instance_connectivity "$ip" "$aws_healthy" 2>/dev/null; then
            echo "⚠ Warning: EC2 is running but not SSH-accessible"
            echo "  Run 'make ec2-health' for detailed diagnostics"
        fi
    elif [ "$state" == "stopped" ]; then
        echo ""
        echo "EC2 is stopped. Use 'make ec2-start' to start it."
    fi
}

start_instance() {
    check_aws_creds
    local instance_id state
    instance_id=$(get_instance_or_exit)
    state=$(get_instance_state "$instance_id")

    if [ "$state" == "running" ]; then
        log_success "Instance is running"
        return 0
    fi

    if [ "$state" != "stopped" ]; then
        log_error "Instance is in state: $state (cannot start)"
        exit 1
    fi

    log_info "Starting instance..."
    aws ec2 start-instances --region "$AWS_REGION" --instance-ids "$instance_id" >/dev/null
    # Add timeout to prevent indefinite hanging (max 5 minutes)
    timeout 300 aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$instance_id" || {
        log_error "Instance failed to start within 5 minutes"
        exit 1
    }

    local ip
    ip=$(get_instance_ip "$instance_id")
    log_info "Waiting for SSH..."

    for _ in {1..120}; do
        if ssh_cmd "$ip" "echo ready" >/dev/null 2>&1; then
            log_success "EC2 ready at $ip"
            # Run EC2 setup (installs dependencies, AWS CLI, etc.)
            setup_ec2 "$ip"
            return 0
        fi
        sleep 2
    done

    log_error "SSH timeout - instance may not be fully ready"
    exit 1
}

stop_instance() {
    check_aws_creds
    local instance_id state
    instance_id=$(get_instance_or_exit)
    state=$(get_instance_state "$instance_id")

    if [ "$state" == "stopped" ]; then
        log_info "Instance already stopped"
        return 0
    fi

    if [ "$state" != "running" ]; then
        log_error "Instance is in state: $state (cannot stop)"
        exit 1
    fi

    log_info "Stopping instance..."
    aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$instance_id" >/dev/null
    log_success "Stop initiated"
}

ssh_instance() {
    check_aws_creds
    local instance_id state ip
    instance_id=$(get_instance_or_exit)
    state=$(get_instance_state "$instance_id")

    if [ "$state" != "running" ]; then
        log_error "Instance is not running (state: $state)"
        exit 1
    fi

    ip=$(get_instance_ip "$instance_id")
    if [ -z "$ip" ] || [ "$ip" == "None" ]; then
        log_error "Could not get instance IP"
        exit 1
    fi

    shift  # Remove 'ssh' from arguments
    if [ $# -eq 0 ]; then
        # Interactive SSH session
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${EC2_USER}@${ip}"
    else
        ssh_cmd "$ip" "$@"
    fi
}

health_check() {
    check_aws_creds
    local instance_id state ip
    instance_id=$(get_instance_or_exit)
    state=$(get_instance_state "$instance_id")
    ip=$(get_instance_ip "$instance_id")

    echo "Instance: $instance_id | State: $state | IP: ${ip:-N/A}"
    echo ""

    # AWS status
    get_instance_system_status "$instance_id"
    check_instance_volumes "$instance_id"
    echo ""

    if [ "$state" != "running" ] || [ -z "$ip" ] || [ "$ip" == "None" ]; then
        echo "Instance is not running"
        return 0
    fi

    # Check AWS health and SSH
    local aws_healthy=false
    local status_output
    status_output=$(aws ec2 describe-instance-status \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --include-all-instances \
        --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
        --output text 2>/dev/null || echo "")

    if [ -n "$status_output" ]; then
        local system_status instance_status
        read -r system_status instance_status <<< "$status_output"
        [ "$system_status" == "ok" ] && [ "$instance_status" == "ok" ] && aws_healthy=true
    fi

    # Check SSH connectivity
    echo "=== Connectivity ==="
    local ssh_accessible=false
    if check_instance_connectivity "$ip" "$aws_healthy"; then
        ssh_accessible=true
    fi
    echo ""

    # Console output - most important for diagnosing hangs
    get_instance_console_output "$instance_id" 100
    echo ""

    if [ "$ssh_accessible" = false ]; then
        check_security_group_ssh "$instance_id"
        echo ""
    else
        # Quick system check when SSH works
        if ! ssh_cmd "$ip" "
            echo '=== System Resources ==='
            free -h | grep -E '^Mem|^Swap'
            df -h / | tail -1
            uptime | awk '{print \"Load:\", \$(NF-2), \$(NF-1), \$NF}'
            echo ''
            echo '=== Top Memory Consumers ==='
            ps aux --sort=-%mem | head -6 | awk '{printf \"  %6s %5.1f%% %s\n\", \$2, \$4, \$11}'
        " 2>/dev/null; then
            echo "  (could not retrieve system info)"
        fi
        echo ""
    fi

    # CloudWatch - only if available, keep it brief
    get_instance_health_metrics "$instance_id" 24
}

ACTION="${1:-status}"

case "$ACTION" in
    status)
        show_status
        ;;
    start)
        start_instance
        ;;
    stop)
        stop_instance
        ;;
    ssh)
        ssh_instance "$@"
        ;;
    health)
        health_check
        ;;
    setup)
        ip=$(get_instance_ip_or_exit)
        setup_ec2 "$ip"
        ;;
    *)
        echo "Usage: $0 [status|start|stop|ssh|health|setup] [args...]"
        echo "  status       - Show instance status (default)"
        echo "  start        - Start/ensure instance is running"
        echo "  stop         - Stop instance"
        echo "  ssh          - SSH into the instance (passes through any additional args)"
        echo "  health       - Run comprehensive health diagnostics"
        echo "  setup        - Re-run EC2 setup (install dependencies, AWS CLI, etc.)"
        exit 1
        ;;
esac
