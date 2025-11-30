#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/controller-config.local.sh" ] && source "$SCRIPT_DIR/controller-config.local.sh"

CONTROLLERS=("${CONTROLLERS[@]:-}")

get_controller_user() {
    local var="CONTROLLER_${1}_USER"
    echo "${!var:-}"
}

get_controller_host() {
    local var="CONTROLLER_${1}_HOST"
    echo "${!var:-}"
}

list_controllers() {
    local IFS=','
    echo "${CONTROLLERS[*]}"
}

is_valid_controller() {
    local name="$1"
    for c in "${CONTROLLERS[@]}"; do
        [ "$c" = "$name" ] && return 0
    done
    return 1
}
