#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SESSION="yocto-build"
ID_FILE="/tmp/ec2-instance-id"
S3_BUCKET="edge-ai-build-artifacts"
YOCTO_DIR="/home/ubuntu/yocto-tegra"
YOCTO_MACHINE="jetson-orin-nano-devkit-nvme"
BUILD_HISTORY_FILE="/home/ubuntu/.ec2-build-history.json"
INSTANCE_TYPE_COSTS='{"c7i.xlarge":0.178,"c7i.2xlarge":0.357,"c7i.4xlarge":0.714,"c6i.xlarge":0.170,"c6i.2xlarge":0.340,"t3.xlarge":0.166,"t3.2xlarge":0.333}'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

get_ec2_id() {
    [ -f "$ID_FILE" ] && cat "$ID_FILE" && return
    local id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
    [ -n "$id" ] && echo "$id" > "$ID_FILE"
    echo "$id"
}

get_region() {
    curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo ""
}

stop_ec2() {
    log "Stopping EC2 $1..."
    local region=$(get_region)
    [ -z "$region" ] && { log "ERROR: Could not get region"; return 1; }
    aws ec2 stop-instances --region "$region" --instance-ids "$1" || { log "ERROR: Stop failed"; return 1; }
    log "Stop initiated"
}

upload_artifacts() {
    log "Uploading artifacts to S3..."
    local region=$(get_region)
    local artifacts_dir="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"
    local archive=$(ls -t "$artifacts_dir"/*.tegraflash.tar.gz 2>/dev/null | head -1)

    if [ -z "$archive" ]; then
        log "ERROR: No tegraflash archive found"
        return 1
    fi

    log "Uploading $(basename "$archive") to s3://$S3_BUCKET/tegraflash.tar.gz"

    aws s3 cp "$archive" "s3://$S3_BUCKET/tegraflash.tar.gz" --region "$region" || {
        log "ERROR: S3 upload failed"
        return 1
    }

    log "Upload complete"
}

record_build() {
    local success="$1"
    local start_time end_time duration_secs instance_type hourly_cost cost
    
    start_time=$(cat /tmp/build-start-time 2>/dev/null || echo "")
    [ -z "$start_time" ] && return
    
    end_time=$(date +%s)
    duration_secs=$((end_time - start_time))
    
    # Get instance type and cost
    instance_type=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")
    hourly_cost=$(echo "$INSTANCE_TYPE_COSTS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$instance_type', 0.35))" 2>/dev/null || echo "0.35")
    cost=$(python3 -c "print(round($duration_secs / 3600 * $hourly_cost, 2))")
    
    # Create or update history file
    python3 - "$BUILD_HISTORY_FILE" "$start_time" "$end_time" "$duration_secs" "$success" "$cost" "$instance_type" << 'PYSCRIPT'
import sys
import json
from datetime import datetime

history_file = sys.argv[1]
start_time = int(sys.argv[2])
end_time = int(sys.argv[3])
duration_secs = int(sys.argv[4])
success = sys.argv[5] == "true"
cost = float(sys.argv[6])
instance_type = sys.argv[7]

# Load existing history
try:
    with open(history_file, 'r') as f:
        history = json.load(f)
except:
    history = {"builds": []}

# Add new entry
history["builds"].append({
    "date": datetime.fromtimestamp(start_time).strftime("%Y-%m-%d"),
    "start": start_time,
    "end": end_time,
    "duration_secs": duration_secs,
    "success": success,
    "cost": cost,
    "instance_type": instance_type
})

# Keep last 20 builds
history["builds"] = history["builds"][-20:]

with open(history_file, 'w') as f:
    json.dump(history, f, indent=2)
PYSCRIPT
    
    rm -f /tmp/build-start-time
    log "Build recorded: ${duration_secs}s, \$${cost}"
}

log "Starting build monitor"

while ! tmux has-session -t "$SESSION" 2>/dev/null; do sleep 2; done
log "Build session detected"

while tmux has-session -t "$SESSION" 2>/dev/null; do sleep 5; done

id=$(get_ec2_id)

# Check if build succeeded
if [ -f /tmp/yocto-build.log ] && grep -q "Tasks Summary:.*all succeeded" /tmp/yocto-build.log 2>/dev/null; then
    log "Build succeeded"
    date +%s > "$YOCTO_DIR/.last-successful-build" 2>/dev/null || true
    record_build "true"
    
    if upload_artifacts; then
        log "Artifacts uploaded, stopping EC2"
        [ -n "$id" ] && stop_ec2 "$id"
    else
        log "ERROR: Upload failed, EC2 will remain running"
    fi
else
    log "Build failed, stopping EC2"
    record_build "false"
    [ -n "$id" ] && stop_ec2 "$id"
fi
