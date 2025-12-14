#!/usr/bin/env python3
"""
Edge AI Device Heartbeat - Updates AWS IoT Device Shadow.

Publishes device state to shadow every interval:
- System metrics (uptime, memory, disk)
- Network status
- Container status
- Timestamp
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

IOT_CONFIG = Path("/data/config/aws-iot/config.json")
HEARTBEAT_INTERVAL = 300  # 5 minutes


def log(msg):
    print(f"[edge-heartbeat] {time.strftime('%Y-%m-%d %H:%M:%S')} {msg}", flush=True)


def get_uptime():
    """Get system uptime in seconds."""
    try:
        with open("/proc/uptime") as f:
            return int(float(f.read().split()[0]))
    except Exception:
        return 0


def get_memory():
    """Get memory usage percentage."""
    try:
        with open("/proc/meminfo") as f:
            lines = f.readlines()
        meminfo = {}
        for line in lines:
            parts = line.split()
            meminfo[parts[0].rstrip(":")] = int(parts[1])
        total = meminfo.get("MemTotal", 1)
        available = meminfo.get("MemAvailable", 0)
        return round((1 - available / total) * 100, 1)
    except Exception:
        return 0


def get_disk_usage():
    """Get /data partition usage percentage."""
    try:
        result = subprocess.run(
            ["df", "/data"],
            capture_output=True, text=True, check=True
        )
        lines = result.stdout.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            return int(parts[4].rstrip("%"))
    except Exception:
        pass
    return 0


def get_container_count():
    """Get number of running containers."""
    try:
        result = subprocess.run(
            ["docker", "ps", "-q"],
            capture_output=True, text=True, check=True
        )
        return len(result.stdout.strip().split("\n")) if result.stdout.strip() else 0
    except Exception:
        return 0


def get_ip_address():
    """Get primary IP address."""
    try:
        result = subprocess.run(
            ["ip", "-4", "-o", "addr", "show", "scope", "global"],
            capture_output=True, text=True, check=True
        )
        for line in result.stdout.splitlines():
            if "docker" not in line and "veth" not in line:
                parts = line.split()
                for i, part in enumerate(parts):
                    if part == "inet":
                        return parts[i + 1].split("/")[0]
    except Exception:
        pass
    return "unknown"


def collect_state():
    """Collect current device state."""
    return {
        "timestamp": int(time.time()),
        "uptime_seconds": get_uptime(),
        "memory_percent": get_memory(),
        "disk_percent": get_disk_usage(),
        "containers_running": get_container_count(),
        "ip_address": get_ip_address(),
    }


class ShadowUpdater:
    """Updates AWS IoT Device Shadow."""

    def __init__(self, config):
        self.endpoint = config["endpoint"]
        self.thing_name = config["thing_name"]
        self.cert_path = config["cert_path"]
        self.key_path = config["key_path"]
        self.ca_path = config["ca_path"]
        self.connected = threading.Event()
        self.published = threading.Event()

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code == 0:
            self.connected.set()
        else:
            log(f"Connection failed: {reason_code}")

    def _on_publish(self, client, userdata, mid, reason_codes, properties):
        self.published.set()

    def update_shadow(self, state):
        """Publish state to device shadow."""
        client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=self.thing_name
        )
        client.on_connect = self._on_connect
        client.on_publish = self._on_publish

        client.tls_set(
            ca_certs=self.ca_path,
            certfile=self.cert_path,
            keyfile=self.key_path,
            tls_version=ssl.PROTOCOL_TLSv1_2
        )

        self.connected.clear()
        self.published.clear()

        client.connect(self.endpoint, 8883, keepalive=60)
        client.loop_start()

        try:
            if not self.connected.wait(timeout=10):
                raise TimeoutError("Connection timeout")

            shadow_payload = {
                "state": {
                    "reported": state
                }
            }

            topic = f"$aws/things/{self.thing_name}/shadow/update"
            result = client.publish(topic, json.dumps(shadow_payload), qos=1)

            if not self.published.wait(timeout=10):
                raise TimeoutError("Publish timeout")

            return True
        finally:
            client.loop_stop()
            client.disconnect()


def main():
    if not IOT_CONFIG.exists():
        log("Device not provisioned, exiting")
        sys.exit(0)

    with open(IOT_CONFIG) as f:
        config = json.load(f)

    updater = ShadowUpdater(config)

    # Run once if called without arguments, loop if called with --daemon
    daemon_mode = "--daemon" in sys.argv

    while True:
        try:
            state = collect_state()
            updater.update_shadow(state)
            log(f"Shadow updated: uptime={state['uptime_seconds']}s mem={state['memory_percent']}% containers={state['containers_running']}")
        except Exception as e:
            log(f"Failed to update shadow: {e}")

        if not daemon_mode:
            break
        time.sleep(HEARTBEAT_INTERVAL)


if __name__ == "__main__":
    main()

