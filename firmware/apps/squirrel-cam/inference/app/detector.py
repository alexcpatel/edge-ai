#!/usr/bin/env python3
"""
TensorRT detector - GPU inference on RTSP streams using Ultralytics YOLO.
Publishes detection events and outputs annotated RTSP stream.
"""

import os
import sys
import json
import socket
import time
import threading
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

# Configuration via environment
SOURCE_URI = os.environ.get("SOURCE_URI", "rtsp://go2rtc:8554/test")
RTSP_PORT = int(os.environ.get("RTSP_PORT", "8555"))
SOCKET_PATH = os.environ.get("SOCKET_PATH", "/tmp/detections.sock")
DETECTION_THRESHOLD = float(os.environ.get("DETECTION_THRESHOLD", "0.5"))
MODEL_PATH = os.environ.get("MODEL_PATH", "/models/yolov8n.engine")

# Target classes (COCO class IDs)
TARGET_CLASSES = {
    14: "bird",
    15: "cat",
    16: "dog",
    # squirrel/chipmunk/raccoon not in COCO - would need custom model
}


def log(msg):
    print(f"[detector] {msg}", flush=True)


class DetectionPublisher:
    """Publishes detection events via Unix socket."""

    def __init__(self, socket_path: str):
        self.socket_path = socket_path
        self.client_path = socket_path + ".client"
        self.sock = None

    def connect(self):
        if self.sock:
            return True
        try:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            self.sock.setblocking(False)
            return True
        except Exception:
            return False

    def publish(self, detection: dict):
        if not self.sock:
            self.connect()
        try:
            msg = json.dumps(detection).encode()
            self.sock.sendto(msg, self.client_path)
        except Exception:
            pass

    def close(self):
        if self.sock:
            self.sock.close()
            self.sock = None


class RTSPServer:
    """Simple RTSP-like server using OpenCV's VideoWriter with GStreamer."""

    def __init__(self, port: int):
        self.port = port
        self.frame = None
        self.lock = threading.Lock()
        self.running = False

    def start(self):
        self.running = True
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()
        log(f"RTSP output on port {self.port}")

    def update_frame(self, frame):
        with self.lock:
            self.frame = frame.copy()

    def _serve(self):
        # GStreamer pipeline for RTSP output
        gst_out = (
            f"appsrc ! videoconvert ! x264enc tune=zerolatency bitrate=2000 ! "
            f"rtph264pay ! udpsink host=127.0.0.1 port=5400"
        )
        out = None

        while self.running:
            with self.lock:
                frame = self.frame

            if frame is not None:
                if out is None:
                    h, w = frame.shape[:2]
                    out = cv2.VideoWriter(gst_out, cv2.CAP_GSTREAMER, 0, 30, (w, h))
                out.write(frame)

            time.sleep(0.03)  # ~30 FPS

        if out:
            out.release()

    def stop(self):
        self.running = False


def download_model():
    """Download and convert model to TensorRT if needed."""
    model_path = Path(MODEL_PATH)

    if model_path.exists():
        log(f"Model found: {MODEL_PATH}")
        return True

    log("Converting YOLOv8n to TensorRT engine...")
    try:
        from ultralytics import YOLO

        # Download and export to TensorRT
        model = YOLO("yolov8n.pt")
        model.export(format="engine", imgsz=640, half=True)

        # Move to models directory
        import shutil
        engine_file = Path("yolov8n.engine")
        if engine_file.exists():
            model_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(engine_file), str(model_path))
            log(f"Model saved to {MODEL_PATH}")
            return True
        else:
            log("Engine file not created")
            return False

    except Exception as e:
        log(f"Model conversion failed: {e}")
        return False


def main():
    log("Starting TensorRT detector...")
    log(f"Source: {SOURCE_URI}")
    log(f"Model: {MODEL_PATH}")
    log(f"Threshold: {DETECTION_THRESHOLD}")

    if not download_model():
        log("Failed to prepare model, exiting")
        sys.exit(1)

    # Load model
    from ultralytics import YOLO
    log("Loading TensorRT model...")
    model = YOLO(MODEL_PATH)
    log("Model loaded")

    # Setup
    publisher = DetectionPublisher(SOCKET_PATH)
    rtsp_server = RTSPServer(RTSP_PORT)
    rtsp_server.start()

    # Open RTSP stream
    log(f"Connecting to {SOURCE_URI}...")
    cap = cv2.VideoCapture(SOURCE_URI)

    if not cap.isOpened():
        log("Failed to open RTSP stream, retrying...")
        time.sleep(5)
        cap = cv2.VideoCapture(SOURCE_URI)
        if not cap.isOpened():
            log("Cannot open RTSP stream")
            sys.exit(1)

    log("Stream connected, starting inference...")

    frame_count = 0
    detection_count = 0
    fps_time = time.time()

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                log("Stream ended or error, reconnecting...")
                time.sleep(2)
                cap.release()
                cap = cv2.VideoCapture(SOURCE_URI)
                continue

            frame_count += 1

            # Run inference
            results = model(frame, conf=DETECTION_THRESHOLD, verbose=False)

            # Process detections
            for r in results:
                boxes = r.boxes
                for box in boxes:
                    cls_id = int(box.cls[0])
                    conf = float(box.conf[0])

                    # Get class name
                    cls_name = model.names.get(cls_id, f"class_{cls_id}")

                    # Check if it's a target class or just log all
                    x1, y1, x2, y2 = map(int, box.xyxy[0])

                    detection = {
                        "timestamp": datetime.now().isoformat(),
                        "frame": frame_count,
                        "class_id": cls_id,
                        "class_name": cls_name,
                        "confidence": round(conf, 3),
                        "bbox": {
                            "left": x1,
                            "top": y1,
                            "width": x2 - x1,
                            "height": y2 - y1,
                        }
                    }

                    detection_count += 1
                    publisher.publish(detection)

                    # Draw on frame
                    cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                    label = f"{cls_name} {conf:.2f}"
                    cv2.putText(frame, label, (x1, y1 - 10),
                               cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

            # Update RTSP output
            rtsp_server.update_frame(frame)

            # Log FPS every 100 frames
            if frame_count % 100 == 0:
                elapsed = time.time() - fps_time
                fps = 100 / elapsed
                log(f"Frame {frame_count}, {detection_count} detections, {fps:.1f} FPS")
                fps_time = time.time()

    except KeyboardInterrupt:
        log("Interrupted")
    finally:
        cap.release()
        rtsp_server.stop()
        publisher.close()
        log(f"Processed {frame_count} frames, {detection_count} detections")


if __name__ == "__main__":
    main()
