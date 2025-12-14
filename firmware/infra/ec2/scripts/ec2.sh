#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/diagnostics.sh"

get_instance_type() {
    aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$1" \
        --query "Reservations[0].Instances[0].InstanceType" --output text 2>/dev/null || echo ""
}

setup_ec2() {
    local ip="$1"
    log_info "Setting up EC2..."
    ssh_cmd "$ip" "YOCTO_MACHINE='$YOCTO_MACHINE' YOCTO_DIR='$YOCTO_DIR' REMOTE_SOURCE_DIR='$REMOTE_SOURCE_DIR' bash -s" \
        < "$SCRIPT_DIR/on-ec2/setup.sh"
    log_success "EC2 setup completed"
}

show_status() {
    check_aws_creds
    "$SCRIPT_DIR/ec2-usage.sh" close 2>/dev/null || true

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
    "$SCRIPT_DIR/ec2-usage.sh" close 2>/dev/null || true

    local id=$(get_instance_or_exit)
    local state=$(get_instance_state "$id")
    local instance_type=$(get_instance_type "$id")

    [ "$state" == "running" ] && { log_success "Instance is running"; return 0; }
    [ "$state" != "stopped" ] && { log_error "Instance is in state: $state (cannot start)"; exit 1; }

    # Auto-restore data volume from snapshot if missing
    restore_data_volume_if_needed "$id"

    log_info "Starting instance..."
    aws ec2 start-instances --region "$AWS_REGION" --instance-ids "$id" >/dev/null
    timeout 300 aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$id" || {
        log_error "Instance failed to start within 5 minutes"; exit 1
    }
    # Record start as soon as instance is running (AWS billing starts here)
    "$SCRIPT_DIR/ec2-usage.sh" start "$instance_type"

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
    [ "$state" == "stopping" ] && { log_info "Instance already stopping"; return 0; }
    [ "$state" != "running" ] && { log_error "Instance is in state: $state (cannot stop)"; exit 1; }

    log_info "Stopping instance..."
    aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$id" >/dev/null
    aws ec2 wait instance-stopped --region "$AWS_REGION" --instance-ids "$id" 2>/dev/null || true
    # Record stop after instance is fully stopped
    "$SCRIPT_DIR/ec2-usage.sh" stop 2>/dev/null || true
    log_success "Instance stopped"
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

# Data volume management (auto-restore on start, auto-archive via Lambda after idle)
get_data_volume_id() {
    aws ec2 describe-volumes --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=yocto-builder-data" "Name=status,Values=available,in-use" \
        --query "Volumes[0].VolumeId" --output text 2>/dev/null || echo ""
}

get_latest_snapshot() {
    aws ec2 describe-snapshots --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=yocto-builder-data-snapshot" \
        --query "Snapshots | sort_by(@, &StartTime) | [-1].SnapshotId" --output text 2>/dev/null || echo ""
}

restore_data_volume_if_needed() {
    local instance_id="$1"

    # Check if volume already exists and is attached
    local vol_id=$(get_data_volume_id)
    if [ -n "$vol_id" ] && [ "$vol_id" != "None" ]; then
        return 0
    fi

    # Get latest snapshot
    local snap_id=$(get_latest_snapshot)
    if [ -z "$snap_id" ] || [ "$snap_id" == "None" ]; then
        log_info "No data volume or snapshot found - will create fresh on setup"
        return 0
    fi

    log_info "Data volume was archived, restoring from snapshot..."

    # Get instance AZ
    local az=$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$instance_id" \
        --query "Reservations[0].Instances[0].Placement.AvailabilityZone" --output text)

    # Create volume from snapshot
    local new_vol=$(aws ec2 create-volume --region "$AWS_REGION" \
        --availability-zone "$az" \
        --snapshot-id "$snap_id" \
        --volume-type gp3 \
        --iops 3000 \
        --throughput 125 \
        --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=yocto-builder-data}]" \
        --query "VolumeId" --output text)

    log_info "Waiting for volume $new_vol..."
    aws ec2 wait volume-available --region "$AWS_REGION" --volume-ids "$new_vol"

    log_info "Attaching volume..."
    aws ec2 attach-volume --region "$AWS_REGION" \
        --volume-id "$new_vol" \
        --instance-id "$instance_id" \
        --device /dev/sdf >/dev/null

    log_success "Data volume restored from snapshot"
}

case "${1:-status}" in
    status) show_status ;;
    start)  start_instance ;;
    stop)   stop_instance ;;
    ssh)    ssh_instance "$@" ;;
    health) health_check ;;
    setup)  setup_ec2 "$(get_instance_ip_or_exit)" ;;
    costs)  "$SCRIPT_DIR/ec2-usage.sh" costs ;;
    *)      echo "Usage: $0 [status|start|stop|ssh|health|setup|costs]"; exit 1 ;;
esac
