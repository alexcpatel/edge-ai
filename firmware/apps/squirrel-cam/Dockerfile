# Squirrel Cam - Edge AI inference for Blink camera clips
#
# Base options (swap as needed):
#   - python:3.11-slim (~150MB, for testing workflow)
#   - dustynv/l4t-pytorch:r36.2.0 (~7GB, for GPU/PyTorch)

FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies
RUN pip3 install --no-cache-dir \
    blinkpy \
    aiohttp \
    aiofiles

# Copy application code
COPY app/ /app/

ENV CONFIG_PATH=/data/config.json
ENV CREDENTIALS_PATH=/data/credentials.json
ENV CLIPS_PATH=/data/clips
ENV PYTHONUNBUFFERED=1

HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep -f "python3 main.py" || exit 1

CMD ["python3", "main.py"]
