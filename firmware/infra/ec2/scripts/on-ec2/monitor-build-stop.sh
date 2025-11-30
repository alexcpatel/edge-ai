#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SESSION="yocto-build"
FLAG="/tmp/auto-stop-ec2"
ID_FILE="/tmp/ec2-instance-id"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

get_ec2_id() {
    [ -f "$ID_FILE" ] && cat "$ID_FILE" && return
    local id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
    [ -n "$id" ] && echo "$id" > "$ID_FILE"
    echo "$id"
}

stop_ec2() {
    log "Stopping EC2 $1..."
    local region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "")
    [ -z "$region" ] && { log "ERROR: Could not get region"; return 1; }
    aws ec2 stop-instances --region "$region" --instance-ids "$1" || { log "ERROR: Stop failed"; return 1; }
    log "Stop initiated"
}

log "Starting build monitor"

while ! tmux has-session -t "$SESSION" 2>/dev/null; do sleep 2; done
log "Build session detected"

while tmux has-session -t "$SESSION" 2>/dev/null; do sleep 5; done

# Record success if build completed
[ -f /tmp/yocto-build.log ] && grep -q "Tasks Summary:.*all succeeded" /tmp/yocto-build.log 2>/dev/null && {
    log "Build succeeded"
    date +%s > /home/ubuntu/yocto-tegra/.last-successful-build 2>/dev/null || true
}

# Auto-stop if flag is set
[ -f "$FLAG" ] && {
    log "Auto-stop enabled"
    id=$(get_ec2_id)
    [ -n "$id" ] && stop_ec2 "$id" || log "ERROR: Could not get EC2 ID"
    rm -f "$FLAG"
}
