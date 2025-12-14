#!/usr/bin/env python3
"""
AWS IoT Fleet Provisioning for Edge AI devices.
Uses claim certificate with MQTT for zero-touch provisioning.
"""

import json
import os
import ssl
import subprocess
import sys
import threading
import time
from pathlib import Path

import paho.mqtt.client as mqtt

IOT_DIR = Path("/data/config/aws-iot")
CLAIM_DIR = Path("/etc/edge-ai/claim")
AMAZON_ROOT_CA_URL = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"


def log(msg):
    print(f"[edge-provision] {time.strftime('%Y-%m-%d %H:%M:%S')} {msg}", flush=True)


def err(msg):
    print(f"[edge-provision] {time.strftime('%Y-%m-%d %H:%M:%S')} ERROR: {msg}", file=sys.stderr, flush=True)


def get_device_serial():
    """Get Jetson serial number from device tree."""
    serial_path = Path("/sys/firmware/devicetree/base/serial-number")
    if serial_path.exists():
        return serial_path.read_text().rstrip('\x00')
    return Path("/etc/machine-id").read_text().strip()


def get_mac_address():
    """Get MAC address of first physical ethernet interface."""
    try:
        result = subprocess.run(
            ["ip", "-o", "link", "show"],
            capture_output=True, text=True, check=True
        )
        for line in result.stdout.splitlines():
            if "ether" in line and not any(x in line for x in ["docker", "lo", "veth"]):
                parts = line.split()
                iface = parts[1].rstrip(":")
                mac_result = subprocess.run(
                    ["ip", "link", "show", iface],
                    capture_output=True, text=True, check=True
                )
                for mac_line in mac_result.stdout.splitlines():
                    if "ether" in mac_line:
                        return mac_line.split()[1].replace(":", "")
    except Exception:
        pass
    return "unknown"


def download_root_ca():
    """Download Amazon Root CA if not present."""
    ca_path = IOT_DIR / "AmazonRootCA1.pem"
    if not ca_path.exists():
        log("Downloading Amazon Root CA...")
        subprocess.run(
            ["curl", "-sf", "-o", str(ca_path), AMAZON_ROOT_CA_URL],
            check=True
        )
    return ca_path


def generate_key_and_csr(thing_name):
    """Generate device private key and CSR."""
    key_path = IOT_DIR / "private.key"
    csr_path = IOT_DIR / "device.csr"

    log("Generating device key pair...")
    subprocess.run([
        "openssl", "ecparam", "-name", "prime256v1",
        "-genkey", "-noout", "-out", str(key_path)
    ], check=True)
    key_path.chmod(0o600)

    subprocess.run([
        "openssl", "req", "-new",
        "-key", str(key_path),
        "-out", str(csr_path),
        "-subj", f"/CN={thing_name}"
    ], check=True)

    return key_path, csr_path


class FleetProvisioner:
    """Handles AWS IoT Fleet Provisioning via MQTT."""

    def __init__(self, endpoint, template_name, thing_name):
        self.endpoint = endpoint
        self.template_name = template_name
        self.thing_name = thing_name
        self.response = None
        self.error = None
        self.response_event = threading.Event()
        self.subscribed_count = 0
        self.expected_subs = 0

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code != 0:
            err(f"Connection failed: {reason_code}")
            self.error = f"Connection failed: {reason_code}"
            self.response_event.set()

    def _on_subscribe(self, client, userdata, mid, reason_codes, properties):
        self.subscribed_count += 1

    def _on_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
            if "/accepted" in msg.topic:
                self.response = payload
            elif "/rejected" in msg.topic:
                self.error = payload.get("errorMessage", str(payload))
            self.response_event.set()
        except Exception as e:
            self.error = str(e)
            self.response_event.set()

    def _on_disconnect(self, client, userdata, disconnect_flags, reason_code, properties):
        if reason_code != 0 and not self.response_event.is_set():
            self.error = f"Disconnected: {reason_code}"
            self.response_event.set()

    def _create_client(self):
        """Create MQTT client with explicit client ID (required for Fleet Provisioning)."""
        client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            protocol=mqtt.MQTTv311,
            client_id=self.thing_name
        )
        client.on_connect = self._on_connect
        client.on_subscribe = self._on_subscribe
        client.on_message = self._on_message
        client.on_disconnect = self._on_disconnect

        client.tls_set(
            ca_certs=str(IOT_DIR / "AmazonRootCA1.pem"),
            certfile=str(CLAIM_DIR / "claim.crt"),
            keyfile=str(CLAIM_DIR / "claim.key"),
            tls_version=ssl.PROTOCOL_TLSv1_2
        )
        return client

    def _mqtt_request(self, sub_topics, pub_topic, payload):
        """Send MQTT request and wait for response."""
        client = self._create_client()
        self.response = None
        self.error = None
        self.response_event.clear()
        self.subscribed_count = 0
        self.expected_subs = len(sub_topics)

        client.connect(self.endpoint, 8883, keepalive=60)
        client.loop_start()

        try:
            time.sleep(0.5)
            for topic in sub_topics:
                client.subscribe(topic, qos=1)

            # Wait for subscriptions
            for _ in range(20):
                if self.subscribed_count >= self.expected_subs:
                    break
                time.sleep(0.1)

            client.publish(pub_topic, json.dumps(payload), qos=1)

            if not self.response_event.wait(timeout=30):
                raise TimeoutError("No response received")
            if self.error:
                raise RuntimeError(self.error)
            return self.response
        finally:
            client.loop_stop()
            client.disconnect()

    def create_certificate_from_csr(self, csr_pem):
        """Request certificate from Fleet Provisioning."""
        log("Requesting certificate from AWS IoT...")
        return self._mqtt_request(
            sub_topics=[
                "$aws/certificates/create-from-csr/json/accepted",
                "$aws/certificates/create-from-csr/json/rejected"
            ],
            pub_topic="$aws/certificates/create-from-csr/json",
            payload={"certificateSigningRequest": csr_pem}
        )

    def register_thing(self, ownership_token, serial, mac):
        """Register thing using provisioning template."""
        log(f"Registering thing: {self.thing_name}")
        topic_base = f"$aws/provisioning-templates/{self.template_name}/provision/json"
        return self._mqtt_request(
            sub_topics=[f"{topic_base}/accepted", f"{topic_base}/rejected"],
            pub_topic=topic_base,
            payload={
                "certificateOwnershipToken": ownership_token,
                "parameters": {
                    "SerialNumber": serial,
                    "MacAddress": mac,
                    "ThingName": self.thing_name
                }
            }
        )


def provision_device():
    """Main provisioning flow."""
    serial = get_device_serial()
    thing_name = f"edge-ai-{serial}"

    log(f"Device serial: {serial}")
    log(f"Provisioning device: {thing_name}")

    # Check if already provisioned
    config_path = IOT_DIR / "config.json"
    if config_path.exists():
        log("Device already provisioned, skipping")
        return True

    # Load claim certificate config
    claim_config_path = CLAIM_DIR / "config.json"
    if not claim_config_path.exists():
        err(f"Claim config not found: {claim_config_path}")
        return False

    with open(claim_config_path) as f:
        claim_config = json.load(f)

    endpoint = claim_config["endpoint"]
    template_name = claim_config["template_name"]

    # Ensure directories exist
    IOT_DIR.mkdir(parents=True, exist_ok=True)

    # Download Root CA
    download_root_ca()

    # Generate key and CSR
    key_path, csr_path = generate_key_and_csr(thing_name)
    csr_pem = csr_path.read_text()

    # Fleet Provisioning
    provisioner = FleetProvisioner(endpoint, template_name, thing_name)

    # Step 1: Create certificate from CSR
    cert_response = provisioner.create_certificate_from_csr(csr_pem)
    cert_pem = cert_response["certificatePem"]
    ownership_token = cert_response["certificateOwnershipToken"]
    log(f"Received certificate: {cert_response['certificateId'][:16]}...")

    # Save certificate
    cert_path = IOT_DIR / "device.crt"
    cert_path.write_text(cert_pem)
    cert_path.chmod(0o600)

    # Step 2: Register thing
    mac = get_mac_address()
    thing_response = provisioner.register_thing(ownership_token, serial, mac)
    log(f"Registered thing: {thing_response['thingName']}")

    # Write final config
    config = {
        "endpoint": endpoint,
        "thing_name": thing_response["thingName"],
        "cert_path": str(cert_path),
        "key_path": str(key_path),
        "ca_path": str(IOT_DIR / "AmazonRootCA1.pem")
    }

    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    config_path.chmod(0o600)

    log("Provisioning complete")
    return True


def main():
    try:
        success = provision_device()
        sys.exit(0 if success else 1)
    except Exception as e:
        err(str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()

