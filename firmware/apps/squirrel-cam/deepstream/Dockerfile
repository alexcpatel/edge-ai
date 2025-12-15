# DeepStream inference container for Jetson Orin
# Uses YOLOv8 with TensorRT for GPU-accelerated animal detection

FROM nvcr.io/nvidia/deepstream-l4t:7.0-samples

ENV DEBIAN_FRONTEND=noninteractive

# Install Python dependencies for DeepStream bindings and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-dev \
    libgstreamer1.0-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --no-cache-dir \
    numpy \
    opencv-python-headless \
    ultralytics \
    onnx \
    onnxruntime

# Create directories
RUN mkdir -p /app /models /config /videos

# Copy application and config
COPY app/ /app/
COPY config/ /config/

WORKDIR /app

# DeepStream Python bindings are included in the base image
ENV PYTHONPATH=/opt/nvidia/deepstream/deepstream/lib:$PYTHONPATH
ENV LD_LIBRARY_PATH=/opt/nvidia/deepstream/deepstream/lib:$LD_LIBRARY_PATH
ENV GST_PLUGIN_PATH=/opt/nvidia/deepstream/deepstream/lib/gst-plugins

# On first run, the model will be converted to TensorRT engine
# This can take several minutes but only happens once
ENV MODEL_PATH=/models/yolov8n.pt
ENV ENGINE_PATH=/models/yolov8n.engine

CMD ["python3", "detector.py"]
