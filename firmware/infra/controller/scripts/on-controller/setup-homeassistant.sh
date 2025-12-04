#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

HOMEASSISTANT_CONFIG_DIR="$HOME/homeassistant"
MATTER_DATA_DIR="$HOME/matter-server"
USERNAME=$(whoami)

echo "Setting up Home Assistant..."

# --- Docker Installation ---
if command -v docker &>/dev/null; then
    echo "Docker already installed"
else
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USERNAME"
    echo "Docker installed (re-login required for group membership)"
fi

if systemctl is-active --quiet docker; then
    echo "Docker service running"
else
    echo "Starting Docker service..."
    sudo systemctl enable docker
    sudo systemctl start docker
fi

# --- Home Assistant Container ---
mkdir -p "$HOMEASSISTANT_CONFIG_DIR"

if docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
    if docker ps --format '{{.Names}}' | grep -q '^homeassistant$'; then
        echo "Home Assistant container running"
    else
        echo "Starting existing Home Assistant container..."
        docker start homeassistant
    fi
else
    echo "Creating Home Assistant container..."
    docker run -d \
        --name homeassistant \
        --privileged \
        --restart=unless-stopped \
        -e TZ="$(cat /etc/timezone 2>/dev/null || echo 'UTC')" \
        -v "$HOMEASSISTANT_CONFIG_DIR:/config" \
        -v /run/dbus:/run/dbus:ro \
        --network=host \
        ghcr.io/home-assistant/home-assistant:stable
    echo "Home Assistant container created"
fi

# --- Matter Server Container ---
mkdir -p "$MATTER_DATA_DIR"

if docker ps -a --format '{{.Names}}' | grep -q '^matter-server$'; then
    if docker ps --format '{{.Names}}' | grep -q '^matter-server$'; then
        echo "Matter Server container running"
    else
        echo "Starting existing Matter Server container..."
        docker start matter-server
    fi
else
    echo "Creating Matter Server container..."
    docker run -d \
        --name matter-server \
        --restart=unless-stopped \
        --security-opt apparmor=unconfined \
        -v "$MATTER_DATA_DIR:/data" \
        -v /run/dbus:/run/dbus:ro \
        --network=host \
        ghcr.io/home-assistant-libs/python-matter-server:stable \
        --storage-path /data --paa-root-cert-dir /data/credentials
    echo "Matter Server container created"
fi

# --- Matter Integration Configuration ---
STORAGE_FILE="$HOMEASSISTANT_CONFIG_DIR/.storage/core.config_entries"

if sudo test -f "$STORAGE_FILE" && sudo grep -q '"domain": "matter"' "$STORAGE_FILE" 2>/dev/null; then
    echo "Matter integration already configured"
elif sudo test -f "$STORAGE_FILE"; then
    echo "Pre-configuring Matter integration..."
    MATTER_ENTRY_ID="matter_$(date +%s)"

    sudo python3 << EOF
import json

storage_file = "$STORAGE_FILE"
matter_entry = {
    "entry_id": "$MATTER_ENTRY_ID",
    "version": 1,
    "minor_version": 1,
    "domain": "matter",
    "title": "Matter",
    "data": {"url": "ws://localhost:5580/ws"},
    "options": {},
    "pref_disable_new_entities": False,
    "pref_disable_polling": False,
    "source": "user",
    "unique_id": None,
    "disabled_by": None
}

with open(storage_file, 'r') as f:
    config = json.load(f)

if not any(e.get('domain') == 'matter' for e in config.get('data', {}).get('entries', [])):
    config.setdefault('data', {}).setdefault('entries', []).append(matter_entry)
    with open(storage_file, 'w') as f:
        json.dump(config, f, indent=2)
    print("Matter integration added to config")
else:
    print("Matter integration already in config")
EOF
else
    echo "Home Assistant not yet initialized. Add Matter integration after first boot:"
    echo "  Settings > Devices & Services > Add Integration > Matter (URL: ws://localhost:5580/ws)"
fi

echo ""
echo "=== Home Assistant Setup Summary ==="
echo "Home Assistant GUI: http://$(hostname -I | awk '{print $1}'):8123"
echo "Matter Server WebSocket: ws://localhost:5580/ws"

