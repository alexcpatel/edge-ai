#!/bin/bash
# NordVPN Meshnet setup for Edge AI devices
# Runs NordVPN in a container for meshnet SSH access

set -euo pipefail

log() { echo "[edge-nordvpn] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
err() { log "ERROR: $*" >&2; }

NORDVPN_DIR="/data/config/nordvpn"
SERVICES_DIR="/data/services"
# Token baked into image at build time (from SSM)
BAKED_TOKEN="/etc/edge-ai/claim/nordvpn-token"

setup_nordvpn_container() {
    log "Setting up NordVPN meshnet container..."

    mkdir -p "$NORDVPN_DIR"

    # Token is baked into image at build time (required)
    cp "$BAKED_TOKEN" "$NORDVPN_DIR/token"
    chmod 600 "$NORDVPN_DIR/token"

    # Pull NordVPN container
    log "Pulling NordVPN container..."
    docker pull ghcr.io/bubuntux/nordvpn:latest

    # Create systemd service for NordVPN meshnet
    cat > "$SERVICES_DIR/nordvpn-meshnet.service" << 'EOF'
[Unit]
Description=NordVPN Meshnet Container
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/docker stop nordvpn-meshnet
ExecStartPre=-/usr/bin/docker rm nordvpn-meshnet
ExecStart=/usr/bin/docker run --rm \
    --name nordvpn-meshnet \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    --sysctl net.ipv4.conf.all.rp_filter=2 \
    --device /dev/net/tun \
    --network host \
    -e TOKEN_FILE=/config/token \
    -e MESHNET=1 \
    -e DNS=103.86.96.100,103.86.99.100 \
    -v /data/config/nordvpn:/config:ro \
    ghcr.io/bubuntux/nordvpn:latest
ExecStop=/usr/bin/docker stop nordvpn-meshnet

[Install]
WantedBy=multi-user.target
EOF

    log "NordVPN meshnet service created"

    # Start the service
    systemctl daemon-reload
    systemctl enable nordvpn-meshnet.service
    systemctl start nordvpn-meshnet.service

    # Wait for meshnet to initialize
    sleep 15

    # Get meshnet hostname for SSH access
    local meshnet_name
    meshnet_name=$(docker exec nordvpn-meshnet nordvpn meshnet peer list 2>/dev/null | grep -oP '[\w-]+\.nord' | head -1 || echo "")

    if [ -n "$meshnet_name" ]; then
        log "Meshnet hostname: $meshnet_name"
        echo "$meshnet_name" > "$NORDVPN_DIR/meshnet-hostname"

        # Report to AWS IoT shadow
        if [ -f /data/config/aws-iot/config.json ]; then
            report_meshnet_to_iot "$meshnet_name"
        fi
    fi
}

report_meshnet_to_iot() {
    local meshnet_name="$1"
    local config_file="/data/config/aws-iot/config.json"

    [ -f "$config_file" ] || return 0

    local endpoint thing_name
    endpoint=$(jq -r '.endpoint' "$config_file")
    thing_name=$(jq -r '.thing_name' "$config_file")

    local shadow_payload
    shadow_payload=$(jq -n \
        --arg hostname "$meshnet_name" \
        '{
            state: {
                reported: {
                    meshnet: {
                        hostname: $hostname,
                        enabled: true
                    }
                }
            }
        }')

    log "Reporting meshnet hostname to IoT shadow..."

    mosquitto_pub \
        --cafile "$(jq -r '.ca_path' "$config_file")" \
        --cert "$(jq -r '.cert_path' "$config_file")" \
        --key "$(jq -r '.key_path' "$config_file")" \
        -h "$endpoint" -p 8883 \
        -t "\$aws/things/${thing_name}/shadow/update" \
        -m "$shadow_payload" || true
}

main() {
    setup_nordvpn_container
}

main "$@"
