#!/usr/bin/env python3
"""
Squirrel Cam - Edge AI inference for Blink camera clips

Watches for new video clips from Home Assistant (Blink integration) and runs
animal detection. Publishes results to MQTT for Home Assistant automations.

Flow:
1. Home Assistant saves Blink motion clips to /data/clips/
2. This service watches for new .mp4 files
3. Runs inference on each clip
4. Publishes detection results to MQTT
"""

import os
import json
import time
from pathlib import Path
from datetime import datetime

import paho.mqtt.client as mqtt
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

CONFIG_PATH = Path(os.environ.get("CONFIG_PATH", "/data/config.json"))
MODEL_PATH = Path(os.environ.get("MODEL_PATH", "/data/model"))
CLIPS_PATH = Path(os.environ.get("CLIPS_PATH", "/data/clips"))

LOG_PREFIX = "[squirrel-cam]"


def log(msg):
    print(f"{LOG_PREFIX} {msg}", flush=True)


def load_config():
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            return json.load(f)
    return {
        "detection_threshold": 0.5,
        "clips_path": "/data/clips",
        "mqtt_broker": "localhost",
        "mqtt_port": 1883,
        "mqtt_topic": "homeassistant/sensor/squirrel_cam/state",
        "classes": ["squirrel", "chipmunk", "bird", "cat", "raccoon"],
        "min_detection_interval_sec": 10,
    }


class ClipHandler(FileSystemEventHandler):
    def __init__(self, detector):
        self.detector = detector

    def on_created(self, event):
        if event.is_directory:
            return
        if event.src_path.endswith(".mp4"):
            # Wait for file to finish writing
            time.sleep(2)
            self.detector.process_clip(Path(event.src_path))


class SquirrelDetector:
    def __init__(self, config):
        self.config = config
        self.mqtt_client = None
        self.last_detection_time = {}

    def connect_mqtt(self):
        try:
            self.mqtt_client = mqtt.Client(
                callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                client_id="squirrel-cam"
            )
            self.mqtt_client.connect(
                self.config.get("mqtt_broker", "localhost"),
                self.config.get("mqtt_port", 1883)
            )
            self.mqtt_client.loop_start()
            log("Connected to MQTT broker")
            self._publish_ha_discovery()
            return True
        except Exception as e:
            log(f"MQTT connection failed: {e}")
            return False

    def _publish_ha_discovery(self):
        discovery_topic = "homeassistant/sensor/squirrel_cam/config"
        discovery_payload = {
            "name": "Squirrel Cam",
            "state_topic": self.config.get("mqtt_topic"),
            "json_attributes_topic": "homeassistant/sensor/squirrel_cam/attributes",
            "unique_id": "edge_ai_squirrel_cam",
            "icon": "mdi:squirrel",
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
        log("Published Home Assistant discovery config")

    def process_clip(self, clip_path: Path):
        log(f"Processing clip: {clip_path.name}")

        # Run detection on clip
        detections = self._run_inference(clip_path)

        if not detections:
            log(f"No detections in {clip_path.name}")
            return

        # Publish each detection
        for detection in detections:
            self._publish_detection(detection, clip_path)

    def _run_inference(self, clip_path: Path) -> list:
        """Run inference on video clip. Returns list of detections."""
        # TODO: Implement actual inference with PyTorch/DeepStream
        # For now, return stub detection for testing
        log(f"Running inference on {clip_path.name} (stub mode)")

        # Stub: simulate detection every few clips
        if hash(clip_path.name) % 3 == 0:
            return [{
                "class": "squirrel",
                "confidence": 0.87,
                "frame": 15,
                "bbox": [120, 80, 280, 240]
            }]
        return []

    def _publish_detection(self, detection: dict, clip_path: Path):
        if not self.mqtt_client:
            return

        animal_class = detection["class"]
        now = time.time()

        # Rate limit
        min_interval = self.config.get("min_detection_interval_sec", 10)
        last_time = self.last_detection_time.get(animal_class, 0)
        if now - last_time < min_interval:
            return

        self.last_detection_time[animal_class] = now

        # Publish state
        state_topic = self.config.get("mqtt_topic")
        self.mqtt_client.publish(state_topic, animal_class)

        # Publish attributes
        attrs = {
            "class": animal_class,
            "confidence": detection["confidence"],
            "clip": clip_path.name,
            "frame": detection.get("frame"),
            "timestamp": datetime.utcnow().isoformat(),
            "bbox": detection.get("bbox", [])
        }
        self.mqtt_client.publish(
            "homeassistant/sensor/squirrel_cam/attributes",
            json.dumps(attrs)
        )

        log(f"Detection: {animal_class} ({detection['confidence']:.0%}) in {clip_path.name}")

    def run(self):
        self.connect_mqtt()

        clips_dir = Path(self.config.get("clips_path", CLIPS_PATH))
        clips_dir.mkdir(parents=True, exist_ok=True)

        log(f"Watching for clips in {clips_dir}")

        # Process any existing clips on startup
        for clip in sorted(clips_dir.glob("*.mp4")):
            self.process_clip(clip)

        # Watch for new clips
        handler = ClipHandler(self)
        observer = Observer()
        observer.schedule(handler, str(clips_dir), recursive=False)
        observer.start()

        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            observer.stop()
            if self.mqtt_client:
                self.mqtt_client.loop_stop()
                self.mqtt_client.disconnect()
        observer.join()


def main():
    log("Starting...")
    config = load_config()
    log(f"Config: threshold={config.get('detection_threshold')}, classes={config.get('classes')}")

    detector = SquirrelDetector(config)
    detector.run()


if __name__ == "__main__":
    main()
