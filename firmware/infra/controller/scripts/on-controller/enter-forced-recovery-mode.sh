#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# GPIO pins (BCM numbering) - adjust based on your wiring
GPIO_FORCE_RECOVERY="${GPIO_FORCE_RECOVERY:-17}"  # Connect to Jetson FC_REC pin
GPIO_RESET="${GPIO_RESET:-27}"                     # Connect to Jetson RST pin
GPIO_POWER="${GPIO_POWER:-22}"                     # Connect to Jetson POWER_BTN pin (optional)

# Timing (milliseconds)
PULSE_DURATION_MS=100
RECOVERY_HOLD_MS=500

is_raspberry_pi() {
    [ -f /proc/device-tree/model ] && grep -qi "raspberry" /proc/device-tree/model 2>/dev/null
}

is_raspberry_pi || { echo "This script only runs on Raspberry Pi"; exit 1; }

command -v pinctrl &>/dev/null || { echo "pinctrl not found. Install: sudo apt install raspi-gpio"; exit 1; }

gpio_output() {
    local pin="$1"
    pinctrl set "$pin" op
}

gpio_high() {
    local pin="$1"
    pinctrl set "$pin" dh
}

gpio_low() {
    local pin="$1"
    pinctrl set "$pin" dl
}

gpio_input() {
    local pin="$1"
    pinctrl set "$pin" ip
}

sleep_ms() {
    local ms="$1"
    sleep "$(echo "scale=3; $ms/1000" | bc)"
}

cleanup() {
    echo "Releasing GPIO pins..."
    gpio_input "$GPIO_FORCE_RECOVERY"
    gpio_input "$GPIO_RESET"
    gpio_input "$GPIO_POWER"
}
trap cleanup EXIT

echo "=== Jetson Forced Recovery Mode ==="
echo "GPIO pins (BCM): FC_REC=$GPIO_FORCE_RECOVERY, RST=$GPIO_RESET, PWR=$GPIO_POWER"
echo ""

# Initialize all pins as inputs (high-impedance)
gpio_input "$GPIO_FORCE_RECOVERY"
gpio_input "$GPIO_RESET"
gpio_input "$GPIO_POWER"

echo "Step 1: Assert FORCE_RECOVERY (pull LOW)"
gpio_output "$GPIO_FORCE_RECOVERY"
gpio_low "$GPIO_FORCE_RECOVERY"
sleep_ms "$PULSE_DURATION_MS"

echo "Step 2: Pulse RESET (LOW for ${PULSE_DURATION_MS}ms)"
gpio_output "$GPIO_RESET"
gpio_low "$GPIO_RESET"
sleep_ms "$PULSE_DURATION_MS"
gpio_input "$GPIO_RESET"

echo "Step 3: Hold FORCE_RECOVERY for ${RECOVERY_HOLD_MS}ms"
sleep_ms "$RECOVERY_HOLD_MS"

echo "Step 4: Release FORCE_RECOVERY"
gpio_input "$GPIO_FORCE_RECOVERY"

echo ""
echo "Jetson should now be in forced recovery mode."
echo "Verify with: lsusb | grep -i nvidia"
