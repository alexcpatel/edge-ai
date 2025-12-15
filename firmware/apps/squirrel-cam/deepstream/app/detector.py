#!/usr/bin/env python3
"""
DeepStream YOLOv8 Detector for Squirrel Cam

Runs GPU-accelerated inference on RTSP streams using DeepStream.
Publishes detection events via Unix socket for the main app to consume.
"""

import os
import sys
import json
import socket
import time
from datetime import datetime
from pathlib import Path

import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst, GLib

import pyds

SOCKET_PATH = os.environ.get("SOCKET_PATH", "/tmp/detections.sock")
CONFIG_PATH = os.environ.get("DS_CONFIG", "/config/deepstream.txt")
SOURCE_URI = os.environ.get("SOURCE_URI", "rtsp://go2rtc:8554/test")
DETECTION_THRESHOLD = float(os.environ.get("DETECTION_THRESHOLD", "0.5"))

TARGET_CLASSES = {
    14: "bird",
    15: "cat",
    16: "dog",
}

COCO_LABELS = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
    "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
    "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
    "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
    "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
    "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
    "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
    "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
    "toothbrush"
]


def log(msg):
    print(f"[detector] {msg}", flush=True)


class DetectionPublisher:
    """Publishes detection events via Unix socket."""

    def __init__(self, socket_path: str):
        self.socket_path = socket_path
        self.sock = None
        self._setup_socket()

    def _setup_socket(self):
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)

        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.sock.bind(self.socket_path)
        os.chmod(self.socket_path, 0o666)
        log(f"Detection socket: {self.socket_path}")

    def publish(self, detection: dict):
        msg = json.dumps(detection).encode()
        try:
            self.sock.sendto(msg, self.socket_path + ".client")
        except Exception:
            pass

    def close(self):
        if self.sock:
            self.sock.close()
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)


class DeepStreamDetector:
    """DeepStream pipeline for YOLOv8 inference."""

    def __init__(self, source_uri: str, publisher: DetectionPublisher):
        self.source_uri = source_uri
        self.publisher = publisher
        self.pipeline = None
        self.loop = None
        self.frame_count = 0
        self.detection_count = 0

    def build_pipeline(self):
        Gst.init(None)

        log(f"Building pipeline for: {self.source_uri}")

        self.pipeline = Gst.Pipeline()

        # Source - RTSP or file
        if self.source_uri.startswith("rtsp://"):
            source = Gst.ElementFactory.make("rtspsrc", "source")
            source.set_property("location", self.source_uri)
            source.set_property("latency", 100)

            depay = Gst.ElementFactory.make("rtph264depay", "depay")
            source.connect("pad-added", self._on_pad_added, depay)
        else:
            source = Gst.ElementFactory.make("filesrc", "source")
            source.set_property("location", self.source_uri)
            depay = Gst.ElementFactory.make("qtdemux", "demux")
            source.connect("pad-added", self._on_pad_added, depay)

        # Decoder
        parser = Gst.ElementFactory.make("h264parse", "parser")
        decoder = Gst.ElementFactory.make("nvv4l2decoder", "decoder")

        # Stream muxer
        streammux = Gst.ElementFactory.make("nvstreammux", "streammux")
        streammux.set_property("batch-size", 1)
        streammux.set_property("width", 1280)
        streammux.set_property("height", 720)
        streammux.set_property("batched-push-timeout", 40000)
        streammux.set_property("live-source", 1)

        # Inference
        pgie = Gst.ElementFactory.make("nvinfer", "pgie")
        pgie.set_property("config-file-path", "/config/infer_yolov8.txt")

        # Tracker
        tracker = Gst.ElementFactory.make("nvtracker", "tracker")
        tracker.set_property("ll-lib-file",
            "/opt/nvidia/deepstream/deepstream/lib/libnvds_nvmultiobjecttracker.so")
        tracker.set_property("ll-config-file",
            "/opt/nvidia/deepstream/deepstream/samples/configs/deepstream-app/config_tracker_NvDCF_perf.yml")
        tracker.set_property("tracker-width", 640)
        tracker.set_property("tracker-height", 384)

        # Video converter for output
        nvvidconv = Gst.ElementFactory.make("nvvideoconvert", "nvvidconv")

        # OSD for visual output
        osd = Gst.ElementFactory.make("nvdsosd", "osd")

        # Output - RTSP server
        nvvidconv2 = Gst.ElementFactory.make("nvvideoconvert", "nvvidconv2")
        encoder = Gst.ElementFactory.make("nvv4l2h264enc", "encoder")
        encoder.set_property("bitrate", 4000000)

        rtppay = Gst.ElementFactory.make("rtph264pay", "rtppay")

        sink = Gst.ElementFactory.make("udpsink", "sink")
        sink.set_property("host", "127.0.0.1")
        sink.set_property("port", 5000)
        sink.set_property("sync", False)

        # Add elements
        elements = [source, parser, decoder, streammux, pgie, tracker,
                   nvvidconv, osd, nvvidconv2, encoder, rtppay, sink]

        if self.source_uri.startswith("rtsp://"):
            elements.insert(1, depay)

        for el in elements:
            if el is None:
                log(f"Failed to create element")
                return False
            self.pipeline.add(el)

        # Link elements (skip source->depay for RTSP, handled via pad-added)
        if self.source_uri.startswith("rtsp://"):
            depay.link(parser)
        else:
            source.link(parser)

        parser.link(decoder)

        # Link decoder to streammux via sinkpad
        decoder_srcpad = decoder.get_static_pad("src")
        mux_sinkpad = streammux.get_request_pad("sink_0")
        decoder_srcpad.link(mux_sinkpad)

        streammux.link(pgie)
        pgie.link(tracker)
        tracker.link(nvvidconv)
        nvvidconv.link(osd)
        osd.link(nvvidconv2)
        nvvidconv2.link(encoder)
        encoder.link(rtppay)
        rtppay.link(sink)

        # Add probe for detection handling
        osd_sinkpad = osd.get_static_pad("sink")
        osd_sinkpad.add_probe(Gst.PadProbeType.BUFFER, self._osd_probe_callback, 0)

        return True

    def _on_pad_added(self, src, pad, target):
        pad.link(target.get_static_pad("sink"))

    def _osd_probe_callback(self, pad, info, user_data):
        gst_buffer = info.get_buffer()
        if not gst_buffer:
            return Gst.PadProbeReturn.OK

        batch_meta = pyds.gst_buffer_get_nvds_batch_meta(hash(gst_buffer))
        if not batch_meta:
            return Gst.PadProbeReturn.OK

        l_frame = batch_meta.frame_meta_list
        while l_frame is not None:
            try:
                frame_meta = pyds.NvDsFrameMeta.cast(l_frame.data)
            except StopIteration:
                break

            self.frame_count += 1

            l_obj = frame_meta.obj_meta_list
            while l_obj is not None:
                try:
                    obj_meta = pyds.NvDsObjectMeta.cast(l_obj.data)
                except StopIteration:
                    break

                class_id = obj_meta.class_id
                confidence = obj_meta.confidence

                if confidence >= DETECTION_THRESHOLD:
                    label = COCO_LABELS[class_id] if class_id < len(COCO_LABELS) else f"class_{class_id}"

                    detection = {
                        "timestamp": datetime.now().isoformat(),
                        "frame": self.frame_count,
                        "class_id": class_id,
                        "class_name": label,
                        "confidence": round(confidence, 3),
                        "track_id": obj_meta.object_id,
                        "bbox": {
                            "left": int(obj_meta.rect_params.left),
                            "top": int(obj_meta.rect_params.top),
                            "width": int(obj_meta.rect_params.width),
                            "height": int(obj_meta.rect_params.height),
                        }
                    }

                    self.detection_count += 1
                    self.publisher.publish(detection)

                    if class_id in TARGET_CLASSES:
                        log(f"Detected {label} (conf={confidence:.2f}, track={obj_meta.object_id})")

                try:
                    l_obj = l_obj.next
                except StopIteration:
                    break

            try:
                l_frame = l_frame.next
            except StopIteration:
                break

        return Gst.PadProbeReturn.OK

    def _on_bus_message(self, bus, message):
        t = message.type
        if t == Gst.MessageType.EOS:
            log("End of stream")
            self.loop.quit()
        elif t == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            log(f"Error: {err}, {debug}")
            self.loop.quit()
        elif t == Gst.MessageType.WARNING:
            err, debug = message.parse_warning()
            log(f"Warning: {err}")
        return True

    def run(self):
        if not self.build_pipeline():
            log("Failed to build pipeline")
            return False

        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._on_bus_message)

        log("Starting pipeline...")
        self.pipeline.set_state(Gst.State.PLAYING)

        self.loop = GLib.MainLoop()
        try:
            self.loop.run()
        except KeyboardInterrupt:
            log("Interrupted")
        finally:
            self.pipeline.set_state(Gst.State.NULL)
            log(f"Processed {self.frame_count} frames, {self.detection_count} detections")

        return True


def download_model():
    """Download YOLOv8n model and convert to ONNX if needed."""
    model_path = Path("/models/yolov8n.onnx")
    if model_path.exists():
        log("Model already exists")
        return True

    log("Downloading YOLOv8n model...")
    try:
        from ultralytics import YOLO
        model = YOLO("yolov8n.pt")
        model.export(format="onnx", imgsz=640, simplify=True)

        # Move to models directory
        Path("yolov8n.onnx").rename(model_path)
        log("Model exported to ONNX")
        return True
    except Exception as e:
        log(f"Failed to download model: {e}")
        return False


def main():
    log("Starting DeepStream detector...")

    if not download_model():
        log("Model download failed, exiting")
        sys.exit(1)

    publisher = DetectionPublisher(SOCKET_PATH)
    detector = DeepStreamDetector(SOURCE_URI, publisher)

    try:
        detector.run()
    finally:
        publisher.close()


if __name__ == "__main__":
    main()
