#!/usr/bin/env python3
"""
Animal Detector - DeepStream-based edge AI inference

Detects animals in RTSP camera feeds and publishes to:
- MQTT (for AWS IoT / Home Assistant integration)
- Home Assistant REST API (optional direct integration)
"""

import os
import sys
import time
import json
import threading
from pathlib import Path
from datetime import datetime

import paho.mqtt.client as mqtt

# Optional: DeepStream Python bindings (available in container)
try:
    import pyds
    DEEPSTREAM_AVAILABLE = True
except ImportError:
    DEEPSTREAM_AVAILABLE = False
    print("[animal-detector] DeepStream not available - running in stub mode")

CONFIG_PATH = Path(os.environ.get("CONFIG_PATH", "/data/config.json"))
MODEL_PATH = Path(os.environ.get("MODEL_PATH", "/data/model"))


def load_config():
    """Load config from mounted volume (allows live updates)."""
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            return json.load(f)
    return {
        "detection_threshold": 0.5,
        "camera_url": "rtsp://localhost:8554/stream",
        "mqtt_broker": "localhost",
        "mqtt_port": 1883,
        "mqtt_topic": "homeassistant/sensor/animal_detector/state",
        "classes": ["cat", "dog", "bird", "deer", "raccoon"],
        "min_detection_interval_sec": 30,
        "home_assistant_url": None,
        "home_assistant_token": None
    }


class AnimalDetector:
    def __init__(self, config):
        self.config = config
        self.mqtt_client = None
        self.last_detection_time = {}
        self.running = False

    def connect_mqtt(self):
        """Connect to MQTT broker for Home Assistant integration."""
        try:
            self.mqtt_client = mqtt.Client(
                callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                client_id="animal-detector"
            )
            self.mqtt_client.connect(
                self.config.get("mqtt_broker", "localhost"),
                self.config.get("mqtt_port", 1883)
            )
            self.mqtt_client.loop_start()
            print(f"[animal-detector] Connected to MQTT broker")

            # Publish Home Assistant discovery config
            self._publish_ha_discovery()
            return True
        except Exception as e:
            print(f"[animal-detector] MQTT connection failed: {e}")
            return False

    def _publish_ha_discovery(self):
        """Publish Home Assistant MQTT discovery config."""
        discovery_topic = "homeassistant/sensor/animal_detector/config"
        discovery_payload = {
            "name": "Animal Detector",
            "state_topic": self.config.get("mqtt_topic", "homeassistant/sensor/animal_detector/state"),
            "json_attributes_topic": "homeassistant/sensor/animal_detector/attributes",
            "unique_id": "edge_ai_animal_detector",
            "device": {
                "identifiers": ["edge_ai_device"],
                "name": "Edge AI Device",
                "manufacturer": "Edge AI",
                "model": "Jetson Orin Nano"
            }
        }
        self.mqtt_client.publish(
            discovery_topic,
            json.dumps(discovery_payload),
            retain=True
        )
        print("[animal-detector] Published Home Assistant discovery config")

    def publish_detection(self, detection):
        """Publish detection event to MQTT."""
        if not self.mqtt_client:
            return

        animal_class = detection["class"]
        now = time.time()

        # Rate limit per class
        min_interval = self.config.get("min_detection_interval_sec", 30)
        last_time = self.last_detection_time.get(animal_class, 0)
        if now - last_time < min_interval:
            return

        self.last_detection_time[animal_class] = now

        # Publish state
        state_topic = self.config.get("mqtt_topic", "homeassistant/sensor/animal_detector/state")
        self.mqtt_client.publish(state_topic, animal_class)

        # Publish attributes
        attrs_topic = "homeassistant/sensor/animal_detector/attributes"
        attrs = {
            "class": animal_class,
            "confidence": detection["confidence"],
            "timestamp": datetime.utcnow().isoformat(),
            "bbox": detection.get("bbox", [])
        }
        self.mqtt_client.publish(attrs_topic, json.dumps(attrs))

        print(f"[animal-detector] Published: {animal_class} ({detection['confidence']:.2f})")

    def run_deepstream_pipeline(self):
        """Run DeepStream inference pipeline."""
        if not DEEPSTREAM_AVAILABLE:
            print("[animal-detector] DeepStream not available, running stub")
            self._run_stub()
            return

        # TODO: Implement actual DeepStream pipeline
        # This would include:
        # 1. GStreamer pipeline with nvstreammux, nvinfer, etc.
        # 2. Custom probe function to extract detections
        # 3. Model loading from MODEL_PATH
        print("[animal-detector] DeepStream pipeline not yet implemented")
        self._run_stub()

    def _run_stub(self):
        """Stub detection loop for testing without DeepStream."""
        iteration = 0
        while self.running:
            iteration += 1

            # Reload config each iteration (enables live parameter tuning)
            self.config = load_config()

            # Simulate occasional detection
            if iteration % 10 == 0:
                detection = {
                    "class": "cat",
                    "confidence": 0.85,
                    "bbox": [100, 100, 200, 200]
                }
                if detection["confidence"] >= self.config.get("detection_threshold", 0.5):
                    self.publish_detection(detection)

            print(f"[animal-detector] Iteration {iteration} - threshold={self.config.get('detection_threshold', 0.5)}")
            time.sleep(5)

    def start(self):
        """Start the detector."""
        self.running = True
        self.connect_mqtt()
        self.run_deepstream_pipeline()

    def stop(self):
        """Stop the detector."""
        self.running = False
        if self.mqtt_client:
            self.mqtt_client.loop_stop()
            self.mqtt_client.disconnect()


def main():
    print("[animal-detector] Starting...")

    config = load_config()
    print(f"[animal-detector] Config loaded from {CONFIG_PATH}")

    if MODEL_PATH.exists():
        print(f"[animal-detector] Model found at: {MODEL_PATH}")
    else:
        print(f"[animal-detector] No model at {MODEL_PATH} - will use default")

    detector = AnimalDetector(config)

    try:
        detector.start()
    except KeyboardInterrupt:
        print("\n[animal-detector] Shutting down...")
        detector.stop()


if __name__ == "__main__":
    main()
