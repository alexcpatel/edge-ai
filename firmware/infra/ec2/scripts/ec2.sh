#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/diagnostics.sh"

get_instance_type() {
    aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$1" \
        --query "Reservations[0].Instances[0].InstanceType" --output text 2>/dev/null || echo ""
}

setup_ec2() {
    local ip="$1"
    log_info "Setting up EC2..."
    ssh_cmd "$ip" "YOCTO_BRANCH='$YOCTO_BRANCH' YOCTO_MACHINE='$YOCTO_MACHINE' \
        YOCTO_DIR='$YOCTO_DIR' REMOTE_SOURCE_DIR='$REMOTE_SOURCE_DIR' bash -s" \
        < "$(dirname "${BASH_SOURCE[0]}")/on-ec2/setup.sh"
    log_success "EC2 setup completed"
}

show_status() {
    check_aws_creds
    local id=$(get_instance_id)
    [ -z "$id" ] || [ "$id" == "None" ] && { echo "Instance: not found"; exit 0; }

    local state=$(get_instance_state "$id")
    local ip=$(get_instance_ip "$id")
    local type=$(get_instance_type "$id")

    echo "Instance ID: $id"
    echo "Instance Type: $type"
    echo "State: $state"
    [ -n "$ip" ] && [ "$ip" != "None" ] && echo "IP: $ip"

    if [ "$state" == "running" ] && [ -n "$ip" ] && [ "$ip" != "None" ]; then
        echo ""
        local status=$(aws ec2 describe-instance-status --region "$AWS_REGION" --instance-ids "$id" \
            --include-all-instances --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
            --output text 2>/dev/null || echo "")
        local healthy=false
        [ -n "$status" ] && read -r sys inst <<< "$status" && [ "$sys" == "ok" ] && [ "$inst" == "ok" ] && healthy=true
        check_instance_connectivity "$ip" "$healthy" 2>/dev/null || {
            echo "⚠ Warning: EC2 is running but not SSH-accessible"
            echo "  Run 'make ec2-health' for detailed diagnostics"
        }
    elif [ "$state" == "stopped" ]; then
        echo -e "\nEC2 is stopped. Use 'make ec2-start' to start it."
    fi
}

start_instance() {
    check_aws_creds
    local id=$(get_instance_or_exit)
    local state=$(get_instance_state "$id")

    [ "$state" == "running" ] && { log_success "Instance is running"; return 0; }
    [ "$state" != "stopped" ] && { log_error "Instance is in state: $state (cannot start)"; exit 1; }

    log_info "Starting instance..."
    aws ec2 start-instances --region "$AWS_REGION" --instance-ids "$id" >/dev/null
    timeout 300 aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$id" || {
        log_error "Instance failed to start within 5 minutes"; exit 1
    }

    local ip=$(get_instance_ip "$id")
    log_info "Waiting for SSH..."
    for _ in {1..120}; do
        ssh_cmd "$ip" "echo ready" >/dev/null 2>&1 && {
            log_success "EC2 ready at $ip"
            return 0
        }
        sleep 2
    done
    log_error "SSH timeout"; exit 1
}

stop_instance() {
    check_aws_creds
    local id=$(get_instance_or_exit)
    local state=$(get_instance_state "$id")

    [ "$state" == "stopped" ] && { log_info "Instance already stopped"; return 0; }
    [ "$state" != "running" ] && { log_error "Instance is in state: $state (cannot stop)"; exit 1; }

    log_info "Stopping instance..."
    aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$id" >/dev/null
    log_success "Stop initiated"
}

ssh_instance() {
    check_aws_creds
    local id=$(get_instance_or_exit)
    local state=$(get_instance_state "$id")
    [ "$state" != "running" ] && { log_error "Instance is not running (state: $state)"; exit 1; }

    local ip=$(get_instance_ip "$id")
    [ -z "$ip" ] || [ "$ip" == "None" ] && { log_error "Could not get instance IP"; exit 1; }

    shift
    [ $# -eq 0 ] && ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${EC2_USER}@${ip}" || ssh_cmd "$ip" "$@"
}

health_check() {
    check_aws_creds
    local id=$(get_instance_or_exit)
    local state=$(get_instance_state "$id")
    local ip=$(get_instance_ip "$id")

    echo "Instance: $id | State: $state | IP: ${ip:-N/A}"
    echo ""
    get_instance_system_status "$id"
    check_instance_volumes "$id"
    echo ""

    [ "$state" != "running" ] || [ -z "$ip" ] || [ "$ip" == "None" ] && { echo "Instance is not running"; return 0; }

    local status=$(aws ec2 describe-instance-status --region "$AWS_REGION" --instance-ids "$id" \
        --include-all-instances --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
        --output text 2>/dev/null || echo "")
    local healthy=false
    [ -n "$status" ] && read -r sys inst <<< "$status" && [ "$sys" == "ok" ] && [ "$inst" == "ok" ] && healthy=true

    echo "=== Connectivity ==="
    local accessible=false
    check_instance_connectivity "$ip" "$healthy" && accessible=true
    echo ""

    get_instance_console_output "$id" 100
    echo ""

    if [ "$accessible" = false ]; then
        check_security_group_ssh "$id"
        echo ""
    else
        ssh_cmd "$ip" "
            echo '=== System Resources ==='
            free -h | grep -E '^Mem|^Swap'
            df -h / | tail -1
            uptime | awk '{print \"Load:\", \$(NF-2), \$(NF-1), \$NF}'
            echo ''
            echo '=== Top Memory Consumers ==='
            ps aux --sort=-%mem | head -6 | awk '{printf \"  %6s %5.1f%% %s\n\", \$2, \$4, \$11}'
        " 2>/dev/null || echo "  (could not retrieve system info)"
        echo ""
    fi
    get_instance_health_metrics "$id" 24
}

case "${1:-status}" in
    status) show_status ;;
    start) start_instance ;;
    stop) stop_instance ;;
    ssh) ssh_instance "$@" ;;
    health) health_check ;;
    setup) setup_ec2 "$(get_instance_ip_or_exit)" ;;
    *) echo "Usage: $0 [status|start|stop|ssh|health|setup]"; exit 1 ;;
esac
