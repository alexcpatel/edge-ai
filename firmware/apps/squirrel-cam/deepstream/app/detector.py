#!/usr/bin/env python3
"""
DeepStream detector - GPU inference on RTSP streams.
Publishes detection events and outputs annotated RTSP stream.
See infer_config.txt to swap models.
"""

import os
import sys
import json
import socket
from datetime import datetime
from pathlib import Path

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GLib, GstRtspServer

import pyds

# Configuration via environment
SOURCE_URI = os.environ.get("SOURCE_URI", "rtsp://go2rtc:8554/test")
RTSP_PORT = int(os.environ.get("RTSP_PORT", "8555"))
SOCKET_PATH = os.environ.get("SOCKET_PATH", "/tmp/detections.sock")
DETECTION_THRESHOLD = float(os.environ.get("DETECTION_THRESHOLD", "0.5"))

# Model configuration - change these to swap models
MODEL_PATH = os.environ.get("MODEL_PATH", "/models/yolov8n.onnx")
MODEL_CONFIG = os.environ.get("MODEL_CONFIG", "/config/infer_config.txt")
LABELS_PATH = os.environ.get("LABELS_PATH", "/config/labels.txt")


def log(msg):
    print(f"[detector] {msg}", flush=True)


def load_labels():
    """Load class labels from file."""
    labels = []
    if Path(LABELS_PATH).exists():
        with open(LABELS_PATH) as f:
            labels = [line.strip() for line in f if line.strip()]
    return labels


LABELS = load_labels()


class DetectionPublisher:
    """Publishes detection events via Unix socket to the app container."""

    def __init__(self, socket_path: str):
        self.socket_path = socket_path
        self.client_path = socket_path + ".client"
        self.sock = None

    def connect(self):
        """Try to connect to the client socket."""
        if self.sock:
            return True
        try:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            self.sock.setblocking(False)
            return True
        except Exception:
            return False

    def publish(self, detection: dict):
        """Send detection event to listener."""
        if not self.sock:
            self.connect()
        try:
            msg = json.dumps(detection).encode()
            self.sock.sendto(msg, self.client_path)
        except (FileNotFoundError, ConnectionRefusedError):
            pass
        except Exception:
            pass

    def close(self):
        if self.sock:
            self.sock.close()
            self.sock = None


class Detector:
    """DeepStream inference pipeline with RTSP output."""

    def __init__(self, publisher: DetectionPublisher):
        self.publisher = publisher
        self.frame_count = 0
        self.detection_count = 0

    def osd_probe(self, pad, info, user_data):
        """Callback for each frame - extracts detections."""
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
                    label = LABELS[class_id] if class_id < len(LABELS) else f"class_{class_id}"

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
                    log(f"Detected {label} (conf={confidence:.2f})")

                try:
                    l_obj = l_obj.next
                except StopIteration:
                    break

            try:
                l_frame = l_frame.next
            except StopIteration:
                break

        return Gst.PadProbeReturn.OK


def make_elm_or_print_err(factoryname, name):
    """Create a GStreamer element or exit with error."""
    elm = Gst.ElementFactory.make(factoryname, name)
    if not elm:
        log(f"Unable to create {factoryname}")
        sys.exit(1)
    return elm


def create_pipeline(detector: Detector):
    """Create the DeepStream pipeline."""
    Gst.init(None)

    pipeline = Gst.Pipeline()

    # Source
    if SOURCE_URI.startswith("rtsp://"):
        source = make_elm_or_print_err("rtspsrc", "source")
        source.set_property("location", SOURCE_URI)
        source.set_property("latency", 200)
        depay = make_elm_or_print_err("rtph264depay", "depay")
    else:
        source = make_elm_or_print_err("filesrc", "source")
        source.set_property("location", SOURCE_URI)
        depay = make_elm_or_print_err("qtdemux", "demux")

    h264parser = make_elm_or_print_err("h264parse", "h264parser")
    decoder = make_elm_or_print_err("nvv4l2decoder", "decoder")

    streammux = make_elm_or_print_err("nvstreammux", "streammux")
    streammux.set_property("batch-size", 1)
    streammux.set_property("width", 1280)
    streammux.set_property("height", 720)
    streammux.set_property("batched-push-timeout", 40000)

    pgie = make_elm_or_print_err("nvinfer", "pgie")
    pgie.set_property("config-file-path", MODEL_CONFIG)

    tracker = make_elm_or_print_err("nvtracker", "tracker")
    tracker.set_property("ll-lib-file", "/opt/nvidia/deepstream/deepstream/lib/libnvds_nvmultiobjecttracker.so")
    tracker.set_property("tracker-width", 640)
    tracker.set_property("tracker-height", 384)

    nvvidconv = make_elm_or_print_err("nvvideoconvert", "nvvidconv")
    nvosd = make_elm_or_print_err("nvdsosd", "nvosd")
    nvvidconv2 = make_elm_or_print_err("nvvideoconvert", "nvvidconv2")

    encoder = make_elm_or_print_err("nvv4l2h264enc", "encoder")
    encoder.set_property("bitrate", 4000000)

    rtppay = make_elm_or_print_err("rtph264pay", "rtppay")
    rtppay.set_property("pt", 96)

    udpsink = make_elm_or_print_err("udpsink", "udpsink")
    udpsink.set_property("host", "127.0.0.1")
    udpsink.set_property("port", 5400)
    udpsink.set_property("sync", False)
    udpsink.set_property("async", False)

    # Add elements to pipeline
    pipeline.add(source)
    pipeline.add(depay)
    pipeline.add(h264parser)
    pipeline.add(decoder)
    pipeline.add(streammux)
    pipeline.add(pgie)
    pipeline.add(tracker)
    pipeline.add(nvvidconv)
    pipeline.add(nvosd)
    pipeline.add(nvvidconv2)
    pipeline.add(encoder)
    pipeline.add(rtppay)
    pipeline.add(udpsink)

    # Link elements
    def on_pad_added(src, pad, sink):
        sinkpad = sink.get_static_pad("sink")
        if not sinkpad.is_linked():
            pad.link(sinkpad)

    source.connect("pad-added", on_pad_added, depay)
    depay.link(h264parser)
    h264parser.link(decoder)

    sinkpad = streammux.get_request_pad("sink_0")
    srcpad = decoder.get_static_pad("src")
    srcpad.link(sinkpad)

    streammux.link(pgie)
    pgie.link(tracker)
    tracker.link(nvvidconv)
    nvvidconv.link(nvosd)
    nvosd.link(nvvidconv2)
    nvvidconv2.link(encoder)
    encoder.link(rtppay)
    rtppay.link(udpsink)

    # Add probe for detections
    osdsinkpad = nvosd.get_static_pad("sink")
    osdsinkpad.add_probe(Gst.PadProbeType.BUFFER, detector.osd_probe, 0)

    return pipeline


def start_rtsp_server():
    """Start RTSP server that reads from UDP and serves to clients."""
    server = GstRtspServer.RTSPServer.new()
    server.set_service(str(RTSP_PORT))

    factory = GstRtspServer.RTSPMediaFactory.new()
    factory.set_launch(
        "( udpsrc port=5400 caps=\"application/x-rtp,media=video,encoding-name=H264\" ! "
        "rtph264depay ! h264parse ! rtph264pay name=pay0 pt=96 )"
    )
    factory.set_shared(True)

    mounts = server.get_mount_points()
    mounts.add_factory("/ds", factory)

    server.attach(None)
    log(f"RTSP server at rtsp://0.0.0.0:{RTSP_PORT}/ds")
    return server


def download_model():
    """Download default model if not present."""
    model_path = Path(MODEL_PATH)
    if model_path.exists():
        log(f"Model found: {MODEL_PATH}")
        return True

    log("Downloading YOLOv8n model (placeholder)...")
    try:
        from ultralytics import YOLO
        model = YOLO("yolov8n.pt")
        model.export(format="onnx", imgsz=640, simplify=True)
        Path("yolov8n.onnx").rename(model_path)
        log(f"Model saved to {MODEL_PATH}")
        return True
    except Exception as e:
        log(f"Model download failed: {e}")
        return False


def bus_callback(bus, message, loop):
    """Handle GStreamer bus messages."""
    t = message.type
    if t == Gst.MessageType.EOS:
        log("End of stream")
        loop.quit()
    elif t == Gst.MessageType.ERROR:
        err, debug = message.parse_error()
        log(f"Error: {err.message}")
        loop.quit()
    return True


def main():
    log("Starting detector...")
    log(f"Source: {SOURCE_URI}")
    log(f"Model: {MODEL_PATH}")
    log(f"Threshold: {DETECTION_THRESHOLD}")

    if not download_model():
        sys.exit(1)

    publisher = DetectionPublisher(SOCKET_PATH)
    detector = Detector(publisher)

    pipeline = create_pipeline(detector)
    rtsp_server = start_rtsp_server()

    loop = GLib.MainLoop()
    bus = pipeline.get_bus()
    bus.add_signal_watch()
    bus.connect("message", bus_callback, loop)

    log("Starting pipeline...")
    pipeline.set_state(Gst.State.PLAYING)

    try:
        loop.run()
    except KeyboardInterrupt:
        log("Interrupted")
    finally:
        pipeline.set_state(Gst.State.NULL)
        publisher.close()
        log(f"Processed {detector.frame_count} frames, {detector.detection_count} detections")


if __name__ == "__main__":
    main()
