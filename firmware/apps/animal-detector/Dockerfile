# Animal Detector - Edge AI inference
#
# Base options (swap as needed):
#   - python:3.11-slim (~150MB, for testing workflow)
#   - dustynv/l4t-pytorch:r36.2.0 (~7GB, for GPU/PyTorch)
#   - nvcr.io/nvidia/deepstream-l4t:7.0-samples (NGC auth, DeepStream)

FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies (use standard PyPI, not Jetson custom indexes)
RUN pip3 install --no-cache-dir --index-url https://pypi.org/simple/ \
    paho-mqtt \
    requests

# Copy application code
COPY app/ /app/

# Config and model paths (mounted from /data on device)
ENV CONFIG_PATH=/data/config.json
ENV MODEL_PATH=/data/model
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD pgrep -f "python3 main.py" || exit 1

CMD ["python3", "main.py"]
