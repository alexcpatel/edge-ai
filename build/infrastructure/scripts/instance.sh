#!/bin/bash
# EC2 instance management tool
# Usage: instance.sh [status|start|stop]

set -e

source "$(dirname "$0")/lib/common.sh"

show_status() {
    check_aws_creds
    instance_id=$(get_instance_id)
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        echo "Instance: not found"
        return 0
    fi

    state=$(get_instance_state "$instance_id")
    ip=$(get_instance_ip "$instance_id")

    echo "Instance ID: $instance_id"
    echo "State: $state"
    [ -n "$ip" ] && [ "$ip" != "None" ] && echo "IP: $ip"
}

start_instance() {
    check_aws_creds
    instance_id=$(get_instance_id)
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        log_error "Instance '$EC2_INSTANCE_NAME' not found"
        exit 1
    fi

    state=$(get_instance_state "$instance_id")

    if [ "$state" == "running" ]; then
        log_success "Instance is running"
        return 0
    elif [ "$state" == "stopped" ]; then
        log_info "Starting instance..."
        aws ec2 start-instances --region "$AWS_REGION" --instance-ids "$instance_id" >/dev/null
        aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$instance_id"

        ip=$(get_instance_ip "$instance_id")
        for i in {1..120}; do
            if ssh_cmd "$ip" "echo ready" >/dev/null 2>&1; then
                log_success "Instance ready at $ip"
                return 0
            fi
            sleep 2
        done
        log_error "SSH timeout"
        exit 1
    else
        log_error "Instance is in state: $state"
        exit 1
    fi
}

stop_instance() {
    check_aws_creds
    instance_id=$(get_instance_id)
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        log_error "Instance not found"
        exit 1
    fi

    state=$(get_instance_state "$instance_id")

    if [ "$state" == "stopped" ]; then
        log_info "Instance already stopped"
    elif [ "$state" == "running" ]; then
        log_info "Stopping instance..."
        aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$instance_id" >/dev/null
        log_success "Stop initiated"
    fi
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
    *)
        echo "Usage: $0 [status|start|stop]"
        echo "  status  - Show instance status (default)"
        echo "  start   - Start/ensure instance is running"
        echo "  stop    - Stop instance"
        exit 1
        ;;
esac
