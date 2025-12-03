#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SESSION="yocto-build"
ID_FILE="/tmp/ec2-instance-id"
S3_BUCKET="edge-ai-build-artifacts"
YOCTO_DIR="/home/ubuntu/yocto-tegra"
YOCTO_MACHINE="jetson-orin-nano-devkit-nvme"

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

log "Starting build monitor"

while ! tmux has-session -t "$SESSION" 2>/dev/null; do sleep 2; done
log "Build session detected"

while tmux has-session -t "$SESSION" 2>/dev/null; do sleep 5; done

id=$(get_ec2_id)

# Check if build succeeded
if [ -f /tmp/yocto-build.log ] && grep -q "Tasks Summary:.*all succeeded" /tmp/yocto-build.log 2>/dev/null; then
    log "Build succeeded"
    date +%s > "$YOCTO_DIR/.last-successful-build" 2>/dev/null || true

    if upload_artifacts; then
        log "Artifacts uploaded, stopping EC2"
        [ -n "$id" ] && stop_ec2 "$id"
    else
        log "ERROR: Upload failed, EC2 will remain running"
    fi
else
    log "Build failed, stopping EC2"
    [ -n "$id" ] && stop_ec2 "$id"
fi
