# DeepStream inference container for Jetson Orin
#
# Current model: YOLOv8n (COCO 80 classes) - placeholder
# To swap with custom SageMaker model:
#   1. Export model to ONNX format
#   2. Mount to /models/model.onnx
#   3. Update labels.txt with your classes
#   4. Update infer_config.txt if input dimensions differ

FROM nvcr.io/nvidia/deepstream-l4t:6.4-samples

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-dev \
    libgstreamer1.0-dev \
    && rm -rf /var/lib/apt/lists/*

# ultralytics used to download/convert YOLOv8 model on first run
RUN pip3 install --no-cache-dir numpy ultralytics onnx

RUN mkdir -p /app /models /config

COPY app/ /app/
COPY config/ /config/

WORKDIR /app

ENV PYTHONPATH=/opt/nvidia/deepstream/deepstream/lib:$PYTHONPATH
ENV LD_LIBRARY_PATH=/opt/nvidia/deepstream/deepstream/lib:$LD_LIBRARY_PATH
ENV GST_PLUGIN_PATH=/opt/nvidia/deepstream/deepstream/lib/gst-plugins

# Model configuration - override to use custom model
ENV MODEL_PATH=/models/yolov8n.onnx
ENV MODEL_CONFIG=/config/infer_config.txt
ENV LABELS_PATH=/config/labels.txt
ENV DETECTION_THRESHOLD=0.5

CMD ["python3", "detector.py"]
