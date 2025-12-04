#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

HA_HOST="http://localhost:8123"
HA_TOKEN_FILE="\$HOME/.homeassistant_token"
PLUG_ENTITY="switch.mini_smart_wi_fi_plug"

usage() {
    echo "Usage: $0 <command> [entity]"
    echo ""
    echo "Commands:"
    echo "  plug-on       Turn on the smart plug"
    echo "  plug-off      Turn off the smart plug"
    echo "  plug-toggle   Toggle the smart plug"
    echo "  plug-status   Get smart plug status"
    echo "  token         Set up Home Assistant API token"
    echo ""
    echo "Requires Home Assistant long-lived access token."
    echo "Create one at: http://<raspberrypi>:8123/profile > Long-Lived Access Tokens"
    exit 1
}

ha_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local cmd="
        TOKEN=\$(cat $HA_TOKEN_FILE 2>/dev/null) || { echo 'No token found. Run: make ha-token'; exit 1; }
        curl -s -X $method \\
            -H 'Authorization: Bearer '\"\$TOKEN\" \\
            -H 'Content-Type: application/json' \\
            ${data:+-d '$data'} \\
            '$HA_HOST/api/$endpoint'
    "
    controller_ssh raspberrypi "$cmd"
}

plug_on() {
    log_info "Turning on plug..."
    ha_api POST "services/switch/turn_on" "{\"entity_id\": \"$PLUG_ENTITY\"}"
    log_success "Plug turned on"
}

plug_off() {
    log_info "Turning off plug..."
    ha_api POST "services/switch/turn_off" "{\"entity_id\": \"$PLUG_ENTITY\"}"
    log_success "Plug turned off"
}

plug_status() {
    local result
    result=$(ha_api GET "states/$PLUG_ENTITY")
    local state
    state=$(echo "$result" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
    echo "Plug status: $state"
}

case "${1:-}" in
    plug-on) plug_on ;;
    plug-off) plug_off ;;
    plug-status) plug_status ;;
    *) usage ;;
esac

