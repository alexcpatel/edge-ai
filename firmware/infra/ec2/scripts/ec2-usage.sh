#!/bin/bash
# EC2 usage tracking - records instance start/stop times and calculates costs
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/common.sh"

USAGE_HISTORY_FILE="$SCRIPT_DIR/../.ec2-usage-history.json"
CURRENT_RUN_FILE="$SCRIPT_DIR/../.ec2-current-run"

# Hourly costs by instance type (on-demand pricing, us-east-2)
get_hourly_cost() {
    case "$1" in
        c7i.xlarge)   echo "0.178" ;;
        c7i.2xlarge)  echo "0.357" ;;
        c7i.4xlarge)  echo "0.714" ;;
        c6i.xlarge)   echo "0.170" ;;
        c6i.2xlarge)  echo "0.340" ;;
        t3.xlarge)    echo "0.166" ;;
        t3.2xlarge)   echo "0.333" ;;
        *)            echo "0.35" ;;
    esac
}

record_start() {
    local instance_type="$1"
    echo "$(date +%s)|$instance_type" > "$CURRENT_RUN_FILE"
}

record_stop() {
    [ ! -f "$CURRENT_RUN_FILE" ] && return 0

    local start_data=$(cat "$CURRENT_RUN_FILE")
    local start_time=$(echo "$start_data" | cut -d'|' -f1)
    local instance_type=$(echo "$start_data" | cut -d'|' -f2)
    local end_time="${1:-$(date +%s)}"
    local duration_secs=$((end_time - start_time))
    local hourly_cost=$(get_hourly_cost "$instance_type")
    local cost=$(echo "scale=3; $duration_secs / 3600 * $hourly_cost" | bc)

    local new_run=$(jq -n \
        --argjson start "$start_time" \
        --argjson end "$end_time" \
        --argjson duration "$duration_secs" \
        --argjson cost "$cost" \
        --arg type "$instance_type" \
        '{start: $start, end: $end, duration_secs: $duration, cost: $cost, instance_type: $type}')

    if [ -f "$USAGE_HISTORY_FILE" ]; then
        jq --argjson new "$new_run" '.runs += [$new] | .runs = .runs[-20:]' "$USAGE_HISTORY_FILE" > "${USAGE_HISTORY_FILE}.tmp"
        mv "${USAGE_HISTORY_FILE}.tmp" "$USAGE_HISTORY_FILE"
    else
        echo "{\"runs\": [$new_run]}" > "$USAGE_HISTORY_FILE"
    fi

    rm -f "$CURRENT_RUN_FILE"
}

# Close orphaned run if EC2 stopped while we weren't connected
close_orphaned() {
    [ ! -f "$CURRENT_RUN_FILE" ] && return 0

    local id=$(get_instance_id)
    [ -z "$id" ] || [ "$id" == "None" ] && return 0

    local state=$(get_instance_state "$id")
    [ "$state" != "stopped" ] && return 0

    # Get the time EC2 transitioned to stopped state (AWS returns UTC)
    local stop_time=$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$id" \
        --query 'Reservations[0].Instances[0].StateTransitionReason' --output text 2>/dev/null | \
        grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)

    if [ -n "$stop_time" ]; then
        # Parse as UTC (AWS times are always UTC)
        local stop_epoch=$(TZ=UTC date -j -f "%Y-%m-%d %H:%M:%S" "$stop_time" +%s 2>/dev/null || date -u -d "$stop_time" +%s 2>/dev/null)
        [ -n "$stop_epoch" ] && record_stop "$stop_epoch" || record_stop
    else
        record_stop
    fi
}

show_costs() {
    close_orphaned
    
    local id=$(get_instance_id)
    local instance_type=""
    [ -n "$id" ] && [ "$id" != "None" ] && instance_type=$(get_instance_type "$id")
    local hourly_cost=$(get_hourly_cost "$instance_type")

    if [ ! -f "$USAGE_HISTORY_FILE" ]; then
        echo "{\"runs\": [], \"total_duration_secs\": 0, \"total_cost\": 0, \"hourly_rate\": $hourly_cost}"
        return
    fi

    jq --argjson rate "$hourly_cost" '{
        runs: (.runs // [])[-5:],
        total_duration_secs: ([(.runs // [])[] | .duration_secs] | add // 0),
        total_cost: ([(.runs // [])[] | .cost] | add // 0),
        hourly_rate: $rate
    }' "$USAGE_HISTORY_FILE"
}

get_instance_type() {
    aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$1" \
        --query "Reservations[0].Instances[0].InstanceType" --output text 2>/dev/null || echo ""
}

# CLI interface
case "${1:-}" in
    start)       record_start "${2:-unknown}" ;;
    stop)        record_stop "${2:-}" ;;
    close)       close_orphaned ;;
    costs|show)  show_costs ;;
    *)           echo "Usage: $0 [start TYPE|stop [TIME]|close|costs]"; exit 1 ;;
esac

