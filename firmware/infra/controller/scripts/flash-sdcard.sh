#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONTROLLER="${CONTROLLER:-steamdeck}"
require_controller "$CONTROLLER"
get_controller_info "$CONTROLLER"

SESSION="sdcard-flash"
LOG_FILE="/tmp/sdcard-flash.log"

is_flash_running() {
    ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" \
        "tmux has-session -t $SESSION 2>/dev/null" >/dev/null 2>&1
}

start_flash() {
    SD_DEVICE="${1:-}"

    is_flash_running && { log_error "Flash already running. Use 'make firmware-controller-flash-sdcard-terminate' first"; exit 1; }

    log_info "=== SD Card Flash Setup ==="

    if [ -z "$SD_DEVICE" ]; then
        log_info "Available devices on controller:"
        check_controller_connection "$CONTROLLER"

        devices_output=$(controller_ssh "$CONTROLLER" "lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -vE '^(NAME|loop)' | grep -E '^(sd|mmc|nvme)' || true" || true)

        if [ -z "$devices_output" ]; then
            log_error "No suitable devices found"
            exit 1
        fi

        declare -a device_names
        declare -a device_sizes
        declare -a device_types
        declare -a device_models

        device_count=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            name=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{print $2}')
            type=$(echo "$line" | awk '{print $3}')
            model=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//' || echo "")

            device_names[$device_count]="$name"
            device_sizes[$device_count]="$size"
            device_types[$device_count]="$type"
            [ -n "$model" ] && device_models[$device_count]="$model" || device_models[$device_count]=""
            device_count=$((device_count + 1))
        done <<< "$devices_output"

        echo ""
        echo "Available devices:"
        for i in $(seq 0 $((device_count - 1))); do
            printf "  %d) /dev/%s" $((i + 1)) "${device_names[$i]}"
            info_parts=()
            [ -n "${device_sizes[$i]}" ] && info_parts+=("${device_sizes[$i]}")
            [ -n "${device_types[$i]}" ] && info_parts+=("${device_types[$i]}")
            [ -n "${device_models[$i]}" ] && info_parts+=("${device_models[$i]}")
            if [ ${#info_parts[@]} -gt 0 ]; then
                printf " (%s)" "$(IFS=', '; echo "${info_parts[*]}")"
            fi
            echo ""
        done
        echo ""

        while true; do
            read -p "Select device (1-$device_count) or press Ctrl+C to cancel: " selection
            [ -z "$selection" ] && { log_error "Selection is required"; continue; }

            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$device_count" ]; then
                selected_idx=$((selection - 1))
                SD_DEVICE="/dev/${device_names[$selected_idx]}"
                log_info "Selected: $SD_DEVICE"
                break
            else
                log_error "Invalid selection. Please enter a number between 1 and $device_count"
            fi
        done
    else
        if [ "$SD_DEVICE" = "${SD_DEVICE#/dev/}" ]; then
            SD_DEVICE="/dev/$SD_DEVICE"
        fi
    fi

    check_controller_connection "$CONTROLLER"

    controller_ssh "$CONTROLLER" "command -v tmux >/dev/null 2>&1" || {
        log_error "tmux is not installed on controller. Run: make firmware-controller-setup C=$CONTROLLER"
        exit 1
    }

    TEGRAFLASH_ARCHIVE=$( (controller_ssh "$CONTROLLER" \
        "ls -t $CURRENT_CONTROLLER_BASE_DIR/tegraflash/*.tegraflash.tar.gz 2>/dev/null | head -1" || echo "") | tr -d '\r\n' | xargs)

    [ -z "$TEGRAFLASH_ARCHIVE" ] && { log_error "No tegraflash archive. Run: make controller-push-tegraflash"; exit 1; }

    controller_ssh "$CONTROLLER" "[ -f '$TEGRAFLASH_ARCHIVE' ]" || {
        log_error "Archive not found on controller: $TEGRAFLASH_ARCHIVE"
        exit 1
    }

    log_info "Using: $(basename "$TEGRAFLASH_ARCHIVE")"

    log_info "Target device: $SD_DEVICE"
    controller_ssh "$CONTROLLER" "lsblk $SD_DEVICE" || true
    echo ""
    echo "WARNING: This will erase all data on $SD_DEVICE"
    echo ""
    read -p "Press Enter to continue, Ctrl+C to cancel..."

    local_script="$SCRIPT_DIR/on-controller/flash-sdcard-device.sh"
    remote_script="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/flash-sdcard-device.sh"
    watch_script="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/watch-flash-sdcard.sh"

    controller_ssh "$CONTROLLER" "mkdir -p $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller"
    controller_rsync "$CONTROLLER" "$local_script" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$remote_script"
    controller_ssh "$CONTROLLER" "chmod +x $remote_script"

    local watch_local="$SCRIPT_DIR/on-controller/watch-flash-sdcard.sh"
    [ -f "$watch_local" ] && {
        controller_rsync "$CONTROLLER" "$watch_local" "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}:$watch_script"
        controller_ssh "$CONTROLLER" "chmod +x $watch_script"
    }

    log_info "Starting flash in persistent session..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" \
        "tmux set -g mouse off 2>/dev/null || true" >/dev/null 2>&1 || true
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" \
        "tmux new-session -d -s $SESSION bash -c 'LOG_FILE=$LOG_FILE bash $remote_script \"$TEGRAFLASH_ARCHIVE\" \"$SD_DEVICE\"'" >/dev/null 2>&1 || {
        log_error "Failed to start flash"; exit 1
    }

    for _ in {1..3}; do is_flash_running && break; sleep 0.5; done
    is_flash_running || { log_error "Flash failed to start"; ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${CURRENT_CONTROLLER_USER}@${CURRENT_CONTROLLER_HOST}" "tail -50 $LOG_FILE" 2>/dev/null || true; exit 1; }

    log_success "Flash started in persistent session"
    log_info "Use 'make firmware-controller-flash-sdcard-watch' to view progress"
}

check_status() {
    check_controller_connection "$CONTROLLER"

    if is_flash_running; then
        echo "Flash session is running"
        local elapsed
        elapsed=$(controller_ssh "$CONTROLLER" "pgrep -f 'dosdcard.sh\|flash-sdcard-device.sh' | head -1 | \
            xargs -I {} ps -o etime= -p {} 2>/dev/null | tr -d ' '" 2>/dev/null || echo "")
        [ -n "$elapsed" ] && echo "Elapsed: $elapsed" || echo "Flash starting..."
        controller_ssh "$CONTROLLER" "tail -5 $LOG_FILE 2>/dev/null" || true
    else
        echo "No flash session found"
    fi
}

watch_flash() {
    check_controller_connection "$CONTROLLER"
    is_flash_running || { log_error "No flash session. Start with 'make firmware-controller-flash-sdcard'"; exit 1; }
    log_info "Watching flash log..."
    controller_ssh "$CONTROLLER" "bash $CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/watch-flash-sdcard.sh" || {
        log_info "Watch ended (flash continues in background)"; exit 0
    }
}

terminate_flash() {
    check_controller_connection "$CONTROLLER"
    is_flash_running || { log_error "No flash session to terminate"; exit 1; }
    log_info "Terminating flash..."
    controller_ssh "$CONTROLLER" "tmux kill-session -t $SESSION 2>/dev/null || true" || true
    controller_ssh "$CONTROLLER" "pkill -f 'dosdcard.sh' 2>/dev/null || true" || true
    log_success "Flash terminated"
}

case "${1:-start}" in
    start) start_flash "${2:-}" ;;
    status) check_status ;;
    watch) watch_flash ;;
    terminate) terminate_flash ;;
    *) echo "Usage: $0 [start|status|watch|terminate] [device]"; exit 1 ;;
esac
