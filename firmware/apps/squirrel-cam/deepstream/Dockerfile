# DeepStream 7.1 for JetPack 6.1 / L4T 36.4
FROM nvcr.io/nvidia/deepstream-l4t:7.1-samples

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip python3-dev python3-gi python3-gst-1.0 \
    gir1.2-gst-rtsp-server-1.0 libgstrtspserver-1.0-dev \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install pyds 1.2.0 for DeepStream 7.1
RUN cd /tmp \
    && wget -q https://github.com/NVIDIA-AI-IOT/deepstream_python_apps/releases/download/v1.2.0/pyds-1.2.0-cp310-cp310-linux_aarch64.whl \
    && pip3 install --no-cache-dir pyds-1.2.0-cp310-cp310-linux_aarch64.whl numpy ultralytics onnx \
    && rm -f pyds-1.2.0-cp310-cp310-linux_aarch64.whl

COPY app/ /app/
COPY config/ /config/

WORKDIR /app

ENV PYTHONPATH=/opt/nvidia/deepstream/deepstream/lib:$PYTHONPATH
ENV MODEL_PATH=/models/yolov8n.onnx
ENV MODEL_CONFIG=/config/infer_config.txt
ENV LABELS_PATH=/config/labels.txt
ENV DETECTION_THRESHOLD=0.5

CMD ["python3", "detector.py"]
