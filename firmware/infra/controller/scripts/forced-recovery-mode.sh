#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/common.sh"

CONTROLLER="raspberrypi"
require_controller "$CONTROLLER"
get_controller_info "$CONTROLLER"

DEVICE_SCRIPT="$CURRENT_CONTROLLER_BASE_DIR/scripts/on-controller/forced-recovery-mode-device.sh"

run_enable() {
    check_controller_connection "$CONTROLLER"
    controller_ssh "$CONTROLLER" "sudo $DEVICE_SCRIPT enable"
}

run_disable() {
    check_controller_connection "$CONTROLLER"
    controller_ssh "$CONTROLLER" "sudo $DEVICE_SCRIPT disable"
}

run_status() {
    check_controller_connection "$CONTROLLER"
    controller_ssh "$CONTROLLER" "sudo $DEVICE_SCRIPT status"
}

usage() {
    echo "Usage: $0 [enable|disable|status]"
    echo ""
    echo "Commands:"
    echo "  enable   Hold FC_REC low (then power cycle Jetson manually)"
    echo "  disable  Release FC_REC"
    echo "  status   Show GPIO state and check for NVIDIA USB device"
    exit 1
}

case "${1:-}" in
    enable) run_enable ;;
    disable) run_disable ;;
    status) run_status ;;
    *) usage ;;
esac
