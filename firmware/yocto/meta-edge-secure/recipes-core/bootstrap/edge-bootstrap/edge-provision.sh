#!/bin/bash
# AWS IoT Fleet Provisioning for Edge AI devices
# Uses claim certificate for zero-touch provisioning

set -euo pipefail

log() { echo "[edge-provision] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
err() { log "ERROR: $*" >&2; }

IOT_DIR="/data/config/aws-iot"
CLAIM_DIR="/etc/edge-ai/claim"  # Baked into rootfs
AMAZON_ROOT_CA="https://www.amazontrust.com/repository/AmazonRootCA1.pem"

get_device_serial() {
    # Jetson serial number from device tree
    if [ -f /sys/firmware/devicetree/base/serial-number ]; then
        tr -d '\0' < /sys/firmware/devicetree/base/serial-number
    else
        cat /etc/machine-id
    fi
}

get_mac_address() {
    ip link show eth0 2>/dev/null | awk '/ether/ {print $2}' | tr -d ':' || echo "unknown"
}

provision_with_fleet() {
    local serial="$1"
    local thing_name="edge-ai-${serial}"

    log "Provisioning device: $thing_name"

    # Load claim certificate config
    if [ ! -f "$CLAIM_DIR/config.json" ]; then
        err "Claim certificate config not found at $CLAIM_DIR/config.json"
        return 1
    fi

    local endpoint template_name
    endpoint=$(jq -r '.endpoint' "$CLAIM_DIR/config.json")
    template_name=$(jq -r '.template_name' "$CLAIM_DIR/config.json")

    mkdir -p "$IOT_DIR"

    # Download Amazon Root CA if not present
    if [ ! -f "$IOT_DIR/AmazonRootCA1.pem" ]; then
        log "Downloading Amazon Root CA..."
        curl -sf -o "$IOT_DIR/AmazonRootCA1.pem" "$AMAZON_ROOT_CA"
    fi

    # Generate device private key
    log "Generating device key pair..."
    openssl ecparam -name prime256v1 -genkey -noout -out "$IOT_DIR/private.key"
    chmod 600 "$IOT_DIR/private.key"

    # Generate CSR
    openssl req -new -key "$IOT_DIR/private.key" \
        -out "$IOT_DIR/device.csr" \
        -subj "/CN=${thing_name}"

    # Fleet provisioning via MQTT
    # Uses mosquitto_pub/sub from claim cert to register and get permanent cert
    log "Requesting certificate from Fleet Provisioning..."

    local csr_json register_payload
    csr_json=$(jq -Rs '.' < "$IOT_DIR/device.csr")

    register_payload=$(jq -n \
        --arg csr "$(<"$IOT_DIR/device.csr")" \
        --arg serial "$serial" \
        --arg mac "$(get_mac_address)" \
        '{
            certificateSigningRequest: $csr,
            parameters: {
                SerialNumber: $serial,
                MacAddress: $mac
            }
        }')

    # Use claim cert to call Fleet Provisioning API
    # Response comes via MQTT - we use a temp file approach with timeout
    local response_file="/tmp/fleet-response-$$"

    # Subscribe to response topic first (in background)
    mosquitto_sub \
        --cafile "$IOT_DIR/AmazonRootCA1.pem" \
        --cert "$CLAIM_DIR/claim.crt" \
        --key "$CLAIM_DIR/claim.key" \
        -h "$endpoint" -p 8883 \
        -t "\$aws/certificates/create-from-csr/json/accepted" \
        -C 1 -W 30 > "$response_file" 2>/dev/null &
    local sub_pid=$!

    sleep 1  # Let subscriber connect

    # Publish CSR request
    echo "$register_payload" | mosquitto_pub \
        --cafile "$IOT_DIR/AmazonRootCA1.pem" \
        --cert "$CLAIM_DIR/claim.crt" \
        --key "$CLAIM_DIR/claim.key" \
        -h "$endpoint" -p 8883 \
        -t "\$aws/certificates/create-from-csr/json" \
        -s

    # Wait for response
    wait $sub_pid || true

    if [ ! -s "$response_file" ]; then
        err "No response from Fleet Provisioning"
        rm -f "$response_file"
        return 1
    fi

    # Extract certificate from response
    local cert_pem cert_id cert_ownership_token
    cert_pem=$(jq -r '.certificatePem' "$response_file")
    cert_id=$(jq -r '.certificateId' "$response_file")
    cert_ownership_token=$(jq -r '.certificateOwnershipToken' "$response_file")

    echo "$cert_pem" > "$IOT_DIR/device.crt"
    chmod 600 "$IOT_DIR/device.crt"

    log "Received certificate: $cert_id"

    # Now register the thing using the provisioning template
    local register_thing_payload
    register_thing_payload=$(jq -n \
        --arg token "$cert_ownership_token" \
        --arg serial "$serial" \
        --arg mac "$(get_mac_address)" \
        '{
            certificateOwnershipToken: $token,
            parameters: {
                SerialNumber: $serial,
                MacAddress: $mac,
                ThingName: ("edge-ai-" + $serial)
            }
        }')

    # Subscribe for thing registration response
    mosquitto_sub \
        --cafile "$IOT_DIR/AmazonRootCA1.pem" \
        --cert "$CLAIM_DIR/claim.crt" \
        --key "$CLAIM_DIR/claim.key" \
        -h "$endpoint" -p 8883 \
        -t "\$aws/provisioning-templates/${template_name}/provision/json/accepted" \
        -C 1 -W 30 > "$response_file" 2>/dev/null &
    sub_pid=$!

    sleep 1

    echo "$register_thing_payload" | mosquitto_pub \
        --cafile "$IOT_DIR/AmazonRootCA1.pem" \
        --cert "$CLAIM_DIR/claim.crt" \
        --key "$CLAIM_DIR/claim.key" \
        -h "$endpoint" -p 8883 \
        -t "\$aws/provisioning-templates/${template_name}/provision/json" \
        -s

    wait $sub_pid || true

    if [ ! -s "$response_file" ]; then
        err "Thing registration failed"
        rm -f "$response_file"
        return 1
    fi

    local registered_thing
    registered_thing=$(jq -r '.thingName' "$response_file")
    log "Registered thing: $registered_thing"

    rm -f "$response_file"

    # Write final config
    jq -n \
        --arg endpoint "$endpoint" \
        --arg thing "$registered_thing" \
        --arg cert "$IOT_DIR/device.crt" \
        --arg key "$IOT_DIR/private.key" \
        --arg ca "$IOT_DIR/AmazonRootCA1.pem" \
        '{
            endpoint: $endpoint,
            thing_name: $thing,
            cert_path: $cert,
            key_path: $key,
            ca_path: $ca
        }' > "$IOT_DIR/config.json"

    chmod 600 "$IOT_DIR/config.json"

    log "Provisioning complete: $registered_thing"
}

main() {
    local serial
    serial=$(get_device_serial)

    log "Device serial: $serial"

    if [ -f "$IOT_DIR/config.json" ]; then
        log "Device already provisioned, skipping"
        exit 0
    fi

    provision_with_fleet "$serial"
}

main "$@"

