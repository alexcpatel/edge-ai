#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$EUID" -eq 0 ] && { echo "Do not run as root"; exit 1; }

CONTROLLER_BASE_DIR="$HOME/edge-ai-controller"

HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
[[ "$HOSTNAME" == *"steamdeck"* || "$HOSTNAME" == *"deck"* ]] && IS_STEAMDECK=true || IS_STEAMDECK=false
grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null && IS_RASPBERRYPI=true || IS_RASPBERRYPI=false

echo "Setting up controller ($(hostname))..."

mkdir -p "$CONTROLLER_BASE_DIR/tegraflash"

USERNAME=$(whoami)
SUDOERS_FILE="/etc/sudoers.d/edge-ai-$USERNAME"
if ! sudo -n true 2>/dev/null; then
    echo "Configuring passwordless sudo for $USERNAME..."
    echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 0440 "$SUDOERS_FILE"
    echo "Passwordless sudo configured"
else
    echo "Passwordless sudo already configured"
fi

if [ "$IS_STEAMDECK" = true ]; then
    PACKAGES=(device-tree-compiler python3 python3-yaml usbutils rsync file libc6-i386 zstd gdisk tmux)
    MISSING=()
    for pkg in "${PACKAGES[@]}"; do
        dpkg -l | grep -q "^ii.*$pkg " 2>/dev/null || MISSING+=("$pkg")
    done

    if [ ${#MISSING[@]} -gt 0 ]; then
        echo "Installing: ${MISSING[*]}"
        dpkg --print-architecture | grep -q i386 2>/dev/null || sudo dpkg --add-architecture i386
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING[@]}"
    fi
fi

if command -v nordvpn &>/dev/null; then
    echo "NordVPN installed. Verify meshnet: nordvpn meshnet peer list"
else
    echo "NordVPN not found. Install: curl -fsSL https://downloads.nordcdn.com/apps/linux/install.sh | sh"
fi

if [ "$IS_RASPBERRYPI" = true ]; then
    source "$SCRIPT_DIR/setup-homeassistant.sh"
fi

echo ""
echo "Setup complete"
