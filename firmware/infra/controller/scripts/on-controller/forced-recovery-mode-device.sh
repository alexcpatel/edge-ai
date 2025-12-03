#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# GPIO pin (BCM numbering)
GPIO_FORCE_RECOVERY="${GPIO_FORCE_RECOVERY:-17}"

usage() {
    echo "Usage: $0 [enable|disable|status]"
    echo ""
    echo "Commands:"
    echo "  enable   Short FC_REC to GND (hold during power cycle to enter recovery)"
    echo "  disable  Release FC_REC (return to normal)"
    echo "  status   Show current GPIO state"
    exit 1
}

is_raspberry_pi() {
    [ -f /proc/device-tree/model ] && grep -qi "raspberry" /proc/device-tree/model 2>/dev/null
}

is_raspberry_pi || { echo "This script only runs on Raspberry Pi"; exit 1; }
command -v pinctrl &>/dev/null || { echo "pinctrl not found"; exit 1; }

# Optocoupler logic:
#   Pi HIGH -> optocoupler conducts -> Jetson FC_REC shorted to GND
#   Pi LOW  -> optocoupler off -> Jetson FC_REC released

gpio_output_low() {
    pinctrl set "$1" op dl
}

gpio_high() {
    pinctrl set "$1" dh
}

gpio_low() {
    pinctrl set "$1" dl
}

gpio_input() {
    pinctrl set "$1" ip
}

show_status() {
    echo "GPIO $GPIO_FORCE_RECOVERY (FC_REC):"
    pinctrl get "$GPIO_FORCE_RECOVERY"
}

do_enable() {
    gpio_output_low "$GPIO_FORCE_RECOVERY"
    gpio_high "$GPIO_FORCE_RECOVERY"
    echo "FC_REC held LOW"
}

do_disable() {
    gpio_low "$GPIO_FORCE_RECOVERY"
    gpio_input "$GPIO_FORCE_RECOVERY"
    echo "FC_REC released"
}

case "${1:-}" in
    enable) do_enable ;;
    disable) do_disable ;;
    status) show_status ;;
    *) usage ;;
esac
