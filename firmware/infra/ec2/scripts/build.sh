#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

is_build_running() {
    ssh_cmd "$1" "tmux has-session -t yocto-build 2>/dev/null" >/dev/null 2>&1
}

upload_source() {
    local ip="$1"
    local dest="${EC2_USER}@${ip}:${REMOTE_SOURCE_DIR}"

    log_info "Uploading source files to EC2..."
    ssh_cmd "$ip" "mkdir -p ${REMOTE_SOURCE_DIR}/firmware/yocto ${REMOTE_SOURCE_DIR}/firmware/infra/ec2/scripts"

    # Upload Yocto config and layers
    rsync_cmd "$ip" -avz --delete \
        "$REPO_ROOT/firmware/yocto/" "$dest/firmware/yocto/"

    # Upload on-EC2 build scripts
    rsync_cmd "$ip" -avz --delete \
        "$REPO_ROOT/firmware/infra/ec2/scripts/on-ec2/" "$dest/firmware/infra/ec2/scripts/on-ec2/"

    log_success "Upload completed"
}

start_build() {
    local ip=$(get_instance_ip_or_exit)

    is_build_running "$ip" && { log_error "Build already running. Use 'make build-terminate' first"; exit 1; }

    upload_source "$ip"
    log_info "Starting Yocto build..."

    ssh_cmd "$ip" "tmux set -g mouse off 2>/dev/null || true" || true

    local kas_config="${REMOTE_SOURCE_DIR}/firmware/yocto/config/kas.yml"
    local build_script="${REMOTE_SOURCE_DIR}/firmware/infra/ec2/scripts/on-ec2/run-build.sh"
    local monitor_script="${REMOTE_SOURCE_DIR}/firmware/infra/ec2/scripts/on-ec2/monitor-build-stop.sh"

    ssh_cmd "$ip" "chmod +x $build_script $monitor_script 2>/dev/null || true" || true
    ssh_cmd "$ip" "tmux new-session -d -s yocto-build bash $build_script '$kas_config' '$YOCTO_DIR'" || {
        log_error "Failed to start build"; exit 1
    }

    # Quick check loop - exits as soon as session is confirmed running
    for i in {1..10}; do
        if is_build_running "$ip"; then
            break
        fi
        # Check if it died (log file exists but session doesn't)
        if ssh_cmd "$ip" "test -f /tmp/yocto-build.log" 2>/dev/null; then
            sleep 0.3
            if ! is_build_running "$ip"; then
                log_error "Build session died immediately. Log output:"
                ssh_cmd "$ip" "cat /tmp/yocto-build.log" || true
                exit 1
            fi
        fi
        sleep 0.2
    done

    is_build_running "$ip" || {
        log_error "Build failed to start"
        ssh_cmd "$ip" "cat /tmp/yocto-build.log 2>/dev/null" || true
        exit 1
    }

    ssh_cmd "$ip" "pkill -f 'monitor-build-stop.sh' 2>/dev/null || true" || true
    ssh_cmd "$ip" "setsid bash $monitor_script > /tmp/build-monitor.log 2>&1 < /dev/null &" || true

    log_success "Build started"
    log_info "Use 'make build-watch' to view progress"
}

check_status() {
    local id=$(get_instance_id)
    [ -z "$id" ] || [ "$id" == "None" ] && { echo "EC2 not found"; exit 1; }

    local state=$(get_instance_state "$id")
    [ "$state" != "running" ] && { echo "EC2 is $state (not running)"; exit 1; }

    local ip=$(get_instance_ip "$id")
    [ -z "$ip" ] || [ "$ip" == "None" ] && { echo "Could not get IP"; exit 1; }

    if ssh_cmd "$ip" "tmux has-session -t yocto-build 2>/dev/null"; then
        echo "Build session is running"

        # Get elapsed time from bitbake/kas process
        local elapsed=$(ssh_cmd "$ip" "pgrep -f 'kas' | head -1 | \
            xargs -I {} ps -o etime= -p {} 2>/dev/null | tr -d ' '" 2>/dev/null || echo "")
        [ -n "$elapsed" ] && echo "Elapsed: $elapsed" || echo "Build starting..."

        # Get task progress from log
        local task=$(ssh_cmd "$ip" "tail -20 /tmp/yocto-build.log 2>/dev/null | \
            grep -oE 'Running task [0-9]+ of [0-9]+' | tail -1" 2>/dev/null || echo "")
        [ -n "$task" ] && echo "Progress: $task"
    else
        echo "No build session found"
        ssh_cmd "$ip" "test -f $YOCTO_DIR/build/bitbake.lock" 2>/dev/null && \
            echo -e "\n⚠ BitBake lock exists - run 'make clean' to fix"
    fi
}

watch_build() {
    local ip=$(get_instance_ip_or_exit)
    is_build_running "$ip" || { log_error "No build session. Start with 'make build'"; exit 1; }
    log_info "Watching build log..."
    ssh_cmd "$ip" "bash ${REMOTE_SOURCE_DIR}/firmware/infra/ec2/scripts/on-ec2/watch-build.sh" || {
        log_info "Watch ended (build continues in background)"; exit 0
    }
}

terminate_build() {
    local ip=$(get_instance_ip_or_exit)
    is_build_running "$ip" || { log_error "No build session to terminate"; exit 1; }
    log_info "Terminating build..."
    ssh_cmd "$ip" "tmux kill-session -t yocto-build 2>/dev/null || true" || true
    ssh_cmd "$ip" "pkill -f 'bitbake' 2>/dev/null; find $YOCTO_DIR -name 'bitbake.lock' -delete 2>/dev/null" || true
    log_success "Build terminated"
}

FLAG_FILE="/tmp/auto-stop-ec2"

set_auto_stop() {
    ssh_cmd "$(get_instance_ip_or_exit)" "touch $FLAG_FILE"
    log_success "Auto-stop enabled"
}

unset_auto_stop() {
    ssh_cmd "$(get_instance_ip_or_exit)" "rm -f $FLAG_FILE"
    log_success "Auto-stop disabled"
}

check_auto_stop() {
    ssh_cmd "$(get_instance_ip_or_exit)" "test -f $FLAG_FILE" 2>/dev/null && echo "enabled" || echo "disabled"
}

case "${1:-start}" in
    start) start_build ;;
    status) check_status ;;
    watch) watch_build ;;
    terminate) terminate_build ;;
    set-auto-stop) set_auto_stop ;;
    unset-auto-stop) unset_auto_stop ;;
    check-auto-stop) check_auto_stop ;;
    *) echo "Usage: $0 [start|status|watch|terminate|set-auto-stop|unset-auto-stop|check-auto-stop]"; exit 1 ;;
esac
