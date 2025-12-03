#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

BUILD_HISTORY_FILE=".ec2-build-history.json"

# Hourly costs by instance type (on-demand pricing, us-east-2)
get_hourly_cost() {
    case "$1" in
        c7i.xlarge)   echo "0.178" ;;
        c7i.2xlarge)  echo "0.357" ;;
        c7i.4xlarge)  echo "0.714" ;;
        c6i.xlarge)   echo "0.170" ;;
        c6i.2xlarge)  echo "0.340" ;;
        c6i.4xlarge)  echo "0.680" ;;
        t3.xlarge)    echo "0.166" ;;
        t3.2xlarge)   echo "0.333" ;;
        *)            echo "0.35" ;; # Default estimate
    esac
}

show_costs() {
    check_aws_creds
    
    local id=$(get_instance_id)
    [ -z "$id" ] || [ "$id" == "None" ] && { echo '{"sessions":[],"total_mins":0,"total_cost":0,"error":"Instance not found"}'; exit 0; }
    
    local ip=$(get_instance_ip "$id")
    local state=$(get_instance_state "$id")
    local instance_type=$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$id" \
        --query "Reservations[0].Instances[0].InstanceType" --output text 2>/dev/null || echo "unknown")
    local hourly_cost=$(get_hourly_cost "$instance_type")
    
    # Try to fetch build history from EC2 (only if running)
    local history_json="{}"
    if [ "$state" == "running" ] && [ -n "$ip" ] && [ "$ip" != "None" ]; then
        history_json=$(ssh_cmd "$ip" "cat ~/$BUILD_HISTORY_FILE 2>/dev/null || echo '{}'" 2>/dev/null || echo "{}")
    fi
    
    # Process history
    python3 - "$history_json" "$hourly_cost" << 'PYSCRIPT'
import json
import sys
from datetime import datetime

history_json = sys.argv[1]
hourly_cost = float(sys.argv[2])

try:
    history = json.loads(history_json)
except:
    history = {}

builds = history.get("builds", [])

if not builds:
    print(json.dumps({"sessions": [], "total_mins": 0, "total_cost": 0, "hourly_rate": hourly_cost}))
    sys.exit(0)

def format_duration(secs):
    if secs < 60:
        return f"{secs}s"
    elif secs < 3600:
        m = secs // 60
        s = secs % 60
        return f"{m}m{s}s" if s > 0 else f"{m}m"
    else:
        h = secs // 3600
        m = (secs % 3600) // 60
        return f"{h}h{m}m" if m > 0 else f"{h}h"

def format_ago(timestamp):
    now = datetime.now().timestamp()
    diff = int(now - timestamp)
    
    if diff < 60:
        return f"{diff}s ago"
    elif diff < 3600:
        m = diff // 60
        return f"{m}m ago"
    elif diff < 86400:
        h = diff // 3600
        return f"{h}h ago"
    else:
        d = diff // 86400
        return f"{d}d ago"

# Last 5 builds, most recent first
result_sessions = []
total_secs = 0

for b in builds[-5:][::-1]:
    duration_secs = b.get("duration_secs", 0)
    cost = b.get("cost", 0)
    total_secs += duration_secs
    
    result_sessions.append({
        "ago": format_ago(b["end"]),
        "duration": format_duration(duration_secs),
        "duration_secs": duration_secs,
        "cost": cost,
        "success": b.get("success", True)
    })

total_cost = sum(s["cost"] for s in result_sessions)

print(json.dumps({
    "sessions": result_sessions,
    "total_mins": round(total_secs / 60, 1),
    "total_cost": round(total_cost, 2),
    "hourly_rate": hourly_cost
}))
PYSCRIPT
}

case "${1:-costs}" in
    costs) show_costs ;;
    *) echo "Usage: $0 [costs]"; exit 1 ;;
esac

