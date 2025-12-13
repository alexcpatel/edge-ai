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

    def __init__(self, endpoint, template_name):
        self.endpoint = endpoint
        self.template_name = template_name
        self.response = None
        self.error = None
        self.response_event = threading.Event()

    def _on_connect(self, client, userdata, flags, rc, properties=None):
        if rc == 0:
            log("Connected to AWS IoT")
        else:
            err(f"Connection failed with code {rc}")
            self.error = f"Connection failed: {rc}"
            self.response_event.set()

    def _on_message(self, client, userdata, msg):
        topic = msg.topic
        try:
            payload = json.loads(msg.payload.decode())
            if "/accepted" in topic:
                self.response = payload
            elif "/rejected" in topic:
                self.error = payload.get("errorMessage", str(payload))
            self.response_event.set()
        except Exception as e:
            err(f"Failed to parse response: {e}")
            self.error = str(e)
            self.response_event.set()

    def _on_disconnect(self, client, userdata, rc, properties=None):
        if rc != 0:
            err(f"Unexpected disconnect: {rc}")

    def _create_client(self):
        """Create and configure MQTT client."""
        client = mqtt.Client(protocol=mqtt.MQTTv311)
        client.on_connect = self._on_connect
        client.on_message = self._on_message
        client.on_disconnect = self._on_disconnect

        ca_path = IOT_DIR / "AmazonRootCA1.pem"
        client.tls_set(
            ca_certs=str(ca_path),
            certfile=str(CLAIM_DIR / "claim.crt"),
            keyfile=str(CLAIM_DIR / "claim.key"),
            tls_version=ssl.PROTOCOL_TLSv1_2
        )

        return client

    def create_certificate_from_csr(self, csr_pem):
        """Request certificate from Fleet Provisioning."""
        log("Requesting certificate from Fleet Provisioning...")

        client = self._create_client()
        self.response = None
        self.error = None
        self.response_event.clear()

        client.connect(self.endpoint, 8883, keepalive=60)
        client.loop_start()

        try:
            time.sleep(1)

            # Subscribe to response topics
            client.subscribe("$aws/certificates/create-from-csr/json/accepted")
            client.subscribe("$aws/certificates/create-from-csr/json/rejected")
            time.sleep(0.5)

            # Publish CSR request
            payload = json.dumps({"certificateSigningRequest": csr_pem})
            client.publish("$aws/certificates/create-from-csr/json", payload)

            # Wait for response
            if not self.response_event.wait(timeout=30):
                raise TimeoutError("No response from Fleet Provisioning")

            if self.error:
                raise RuntimeError(f"Fleet Provisioning error: {self.error}")

            return self.response

        finally:
            client.loop_stop()
            client.disconnect()

    def register_thing(self, ownership_token, serial, mac, thing_name):
        """Register thing using provisioning template."""
        log(f"Registering thing with template: {self.template_name}")

        client = self._create_client()
        self.response = None
        self.error = None
        self.response_event.clear()

        client.connect(self.endpoint, 8883, keepalive=60)
        client.loop_start()

        try:
            time.sleep(1)

            # Subscribe to response topics
            topic_base = f"$aws/provisioning-templates/{self.template_name}/provision/json"
            client.subscribe(f"{topic_base}/accepted")
            client.subscribe(f"{topic_base}/rejected")
            time.sleep(0.5)

            # Publish registration request
            payload = json.dumps({
                "certificateOwnershipToken": ownership_token,
                "parameters": {
                    "SerialNumber": serial,
                    "MacAddress": mac,
                    "ThingName": thing_name
                }
            })
            client.publish(topic_base, payload)

            # Wait for response
            if not self.response_event.wait(timeout=30):
                raise TimeoutError("No response from RegisterThing")

            if self.error:
                raise RuntimeError(f"RegisterThing error: {self.error}")

            return self.response

        finally:
            client.loop_stop()
            client.disconnect()


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
    provisioner = FleetProvisioner(endpoint, template_name)

    # Step 1: Create certificate from CSR
    cert_response = provisioner.create_certificate_from_csr(csr_pem)

    cert_pem = cert_response["certificatePem"]
    cert_id = cert_response["certificateId"]
    ownership_token = cert_response["certificateOwnershipToken"]

    # Save certificate
    cert_path = IOT_DIR / "device.crt"
    cert_path.write_text(cert_pem)
    cert_path.chmod(0o600)

    log(f"Received certificate: {cert_id}")

    # Step 2: Register thing
    mac = get_mac_address()
    thing_response = provisioner.register_thing(ownership_token, serial, mac, thing_name)

    registered_thing = thing_response["thingName"]
    log(f"Registered thing: {registered_thing}")

    # Write final config
    config = {
        "endpoint": endpoint,
        "thing_name": registered_thing,
        "cert_path": str(cert_path),
        "key_path": str(key_path),
        "ca_path": str(IOT_DIR / "AmazonRootCA1.pem")
    }

    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    config_path.chmod(0o600)

    log(f"Provisioning complete: {registered_thing}")
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

