#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Instance diagnostics and health check functions
# Used for troubleshooting instance issues when SSH is not accessible

# Source common.sh from the same directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

get_instance_health_metrics() {
    local instance_id="$1"
    local hours="${2:-24}"  # Default to 24 hours, can override
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        return 1
    fi

    # Get CloudWatch metrics for the specified time period
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    # Try BSD date (macOS) first, then GNU date (Linux)
    local start_time
    if command -v gdate >/dev/null 2>&1; then
        start_time=$(gdate -u -d "$hours hours ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null)
    else
        # Try BSD date (macOS)
        start_time=$(date -u -v-"${hours}"H +%Y-%m-%dT%H:%M:%S 2>/dev/null || \
                      date -u -d "$hours hours ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null || \
                      date -u -v-"${hours}"H +%Y-%m-%dT%H:%M:%S)
    fi

    # Check if metrics are available (don't show if not)
    local test_metric
    test_metric=$(aws cloudwatch get-metric-statistics \
        --region "$AWS_REGION" \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --output text 2>/dev/null | wc -l)

    if [ "$test_metric" -lt 2 ]; then
        # Metrics not available - don't show anything
        return 0
    fi

    echo "=== CloudWatch Metrics (last $hours hours) ==="

    # Check for status check failures (most important)
    local status_failures
    status_failures=$(aws cloudwatch get-metric-statistics \
        --region "$AWS_REGION" \
        --namespace AWS/EC2 \
        --metric-name StatusCheckFailed \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Sum \
        --output text 2>/dev/null | grep -v "^$" | tail -5 | awk '{sum+=$2} END {print sum+0}')

    if [ -n "$status_failures" ] && [ "$status_failures" != "0" ] && [ "$(echo "$status_failures > 0" | bc 2>/dev/null || echo 0)" = "1" ]; then
        echo "  ⚠ Status check failures: $status_failures (instance was unresponsive)"
    fi

    # Show recent CPU max (to spot spikes)
    local cpu_max
    cpu_max=$(aws cloudwatch get-metric-statistics \
        --region "$AWS_REGION" \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Maximum \
        --output text 2>/dev/null | tail -1 | awk '{print $2}')

    if [ -n "$cpu_max" ] && [ "$cpu_max" != "None" ]; then
        printf "  CPU max: %.1f%%\n" "$cpu_max"
    fi
}

get_instance_system_status() {
    local instance_id="$1"
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        return 1
    fi

    echo "=== AWS Instance Status ==="
    local status_output
    status_output=$(aws ec2 describe-instance-status \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --include-all-instances \
        --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status,InstanceState.Name]' \
        --output text 2>/dev/null)

    if [ -n "$status_output" ]; then
        local system_status instance_status state
        read -r system_status instance_status state <<< "$status_output"
        echo "  System Status: $system_status"
        echo "  Instance Status: $instance_status"
        echo "  State: $state"
    else
        echo "  (Status check unavailable)"
    fi
}

get_instance_console_output() {
    local instance_id="$1"
    local lines="${2:-100}"
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        return 1
    fi

    echo "=== Console Output (key diagnostic for hangs) ==="
    local console_output
    console_output=$(aws ec2 get-console-output \
        --region "$AWS_REGION" \
        --instance-id "$instance_id" \
        --latest \
        --query 'Output' \
        --output text 2>/dev/null)

    if [ -z "$console_output" ]; then
        echo "  (unavailable - may take a few minutes after boot)"
        return 0
    fi

    # Check for critical errors first
    local oom_count panic_count
    oom_count=$(echo "$console_output" | grep -ci "out of memory\|oom\|killed process" || echo "0")
    panic_count=$(echo "$console_output" | grep -ci "kernel panic\|panic:" || echo "0")

    if [ "$oom_count" -gt 0 ]; then
        echo "  ⚠ OOM detected: $oom_count event(s)"
        echo ""
        echo "$console_output" | grep -i "out of memory\|oom-kill\|killed process" | tail -3 | sed 's/^/  /'
    elif [ "$panic_count" -gt 0 ]; then
        echo "  ⚠ Kernel panic detected: $panic_count event(s)"
        echo ""
        echo "$console_output" | grep -i "kernel panic\|panic:" | tail -5 | sed 's/^/  /'
    else
        # No critical errors, show recent output
        local recent_output
        recent_output=$(echo "$console_output" | tail -20)
        if echo "$recent_output" | grep -qiE "error|fail|warn"; then
            echo "  Recent errors/warnings found:"
            echo "$recent_output" | grep -iE "error|fail|warn" | tail -5 | sed 's/^/  /'
        else
            echo "  (No critical errors found - showing last 10 lines)"
            echo "$console_output" | tail -10 | sed 's/^/  /'
        fi
    fi
}

check_security_group_ssh() {
    local instance_id="$1"
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        return 1
    fi

    echo "=== Security Group SSH Access ==="
    local sg_ids
    sg_ids=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
        --output text 2>/dev/null)

    if [ -z "$sg_ids" ]; then
        echo "  (Could not retrieve security groups)"
        return 1
    fi

    local has_ssh=false
    for sg_id in $sg_ids; do
        local ssh_rules
        ssh_rules=$(aws ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` || ToPort==`22`]' \
            --output json 2>/dev/null)

        if [ -n "$ssh_rules" ] && [ "$ssh_rules" != "[]" ]; then
            has_ssh=true
            echo "  Security Group: $sg_id"
            echo "$ssh_rules" | grep -E '(FromPort|ToPort|CidrIp|IpProtocol)' | head -10 | sed 's/^/    /'
            break
        fi
    done

    if [ "$has_ssh" = false ]; then
        echo "  ⚠ No SSH (port 22) rules found in security groups"
        echo "    This could explain why SSH is not accessible"
    fi
}

check_instance_volumes() {
    local instance_id="$1"
    if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
        return 1
    fi

    echo "=== Attached EBS Volumes ==="
    local volumes
    volumes=$(aws ec2 describe-volumes \
        --region "$AWS_REGION" \
        --filters "Name=attachment.instance-id,Values=$instance_id" \
        --query 'Volumes[*].[VolumeId,Size,State,Attachments[0].Device,Attachments[0].DeleteOnTermination,VolumeType,CreateTime]' \
        --output text 2>/dev/null)

    if [ -n "$volumes" ]; then
        echo "  Volume ID          Size    State      Device      Del?  Type      Created"
        echo "$volumes" | while read -r vol_id size state device delete_on_term vol_type create_time; do
            local created_date
            created_date=$(echo "$create_time" | cut -d'T' -f1)
            printf "  %-18s %-7s %-10s %-11s %-5s %-9s %s\n" \
                "$vol_id" "${size}GB" "$state" "$device" "$delete_on_term" "$vol_type" "$created_date"
        done
        echo ""
        echo "  Note: /dev/xvda maps to nvme0n1, /dev/xvdb maps to nvme1n1, etc."
        echo "  Any unmounted NVMe devices (e.g., nvme1n1) are likely instance store volumes"
        echo "  (ephemeral storage that comes with certain instance types - not persistent)"
    else
        echo "  (No volumes found or could not retrieve volume info)"
    fi
}

check_instance_connectivity() {
    local ip="$1"
    local show_aws_warning="${2:-false}"

    if [ -z "$ip" ] || [ "$ip" == "None" ]; then
        return 1
    fi

    # Use timeout to prevent hanging
    if timeout 10 ssh -i "$EC2_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        "${EC2_USER}@${ip}" \
        "echo 'SSH: OK'" >/dev/null 2>&1; then
        echo "SSH: ✓ Accessible"
        return 0
    else
        echo "SSH: ✗ Not accessible"
        if [ "$show_aws_warning" = "true" ]; then
            echo "  ⚠ AWS reports healthy but SSH failing - likely system hang"
        fi
        return 1
    fi
}

