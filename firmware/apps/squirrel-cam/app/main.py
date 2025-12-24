#!/usr/bin/env python3
"""
Squirrel Cam - Detection event handler

Listens for detection events from inference container and handles alerts.
"""

import os
import json
import asyncio
import socket

SOCKET_PATH = os.environ.get("SOCKET_PATH", "/tmp/detections.sock")
DETECTION_THRESHOLD = float(os.environ.get("DETECTION_THRESHOLD", "0.5"))

TARGET_CLASSES = {"bird", "cat", "dog", "squirrel", "chipmunk", "raccoon"}


def log(msg):
    print(f"[squirrel-cam] {msg}", flush=True)


class DetectionListener:
    """Listen for detection events via Unix socket."""

    def __init__(self):
        self.threshold = DETECTION_THRESHOLD
        self.sock = None
        self.recent_detections = {}

    def setup_socket(self):
        client_path = SOCKET_PATH + ".client"
        if os.path.exists(client_path):
            os.unlink(client_path)

        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.sock.bind(client_path)
        self.sock.setblocking(False)
        log(f"Listening on {client_path}")

    async def run(self):
        self.setup_socket()
        log("Waiting for detection events...")

        loop = asyncio.get_event_loop()

        while True:
            try:
                data = await loop.sock_recv(self.sock, 4096)
                detection = json.loads(data.decode())
                self.handle_detection(detection)
            except BlockingIOError:
                await asyncio.sleep(0.01)
            except json.JSONDecodeError:
                continue
            except Exception as e:
                log(f"Error receiving detection: {e}")
                await asyncio.sleep(1)

    def handle_detection(self, detection: dict):
        class_name = detection.get("class_name", "")
        confidence = detection.get("confidence", 0)
        track_id = detection.get("track_id", 0)

        if confidence < self.threshold:
            return

        if class_name not in TARGET_CLASSES:
            return

        # Dedupe by track_id - only alert once per tracked object
        if track_id in self.recent_detections:
            return

        self.recent_detections[track_id] = detection
        self.on_target_detected(detection)

        # Cleanup old tracks after 1000 entries
        if len(self.recent_detections) > 1000:
            self.recent_detections.clear()

    def on_target_detected(self, detection: dict):
        class_name = detection["class_name"]
        confidence = detection["confidence"]
        timestamp = detection.get("timestamp", "")

        if class_name == "squirrel":
            log(f"🐿️  SQUIRREL detected! conf={confidence:.2f} at {timestamp}")
        else:
            log(f"Detected {class_name} (conf={confidence:.2f})")

    def cleanup(self):
        if self.sock:
            self.sock.close()
        client_path = SOCKET_PATH + ".client"
        if os.path.exists(client_path):
            os.unlink(client_path)


async def main():
    log("Starting detection listener...")
    log(f"Threshold: {DETECTION_THRESHOLD}")

    listener = DetectionListener()
    try:
        await listener.run()
    finally:
        listener.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
