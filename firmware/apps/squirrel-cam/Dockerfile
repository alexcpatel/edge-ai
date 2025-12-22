# Squirrel Cam - Detection event handler
#
# Listens for detection events from DeepStream container.
# Also includes auth.py for Blink authentication.

FROM python:3.11-slim

WORKDIR /app

# blinkpy/aiohttp needed for auth.py (Blink authentication)
RUN pip3 install --no-cache-dir blinkpy aiohttp

COPY app/ /app/

ENV PYTHONUNBUFFERED=1
ENV SOCKET_PATH=/tmp/detections.sock
ENV DETECTION_THRESHOLD=0.5

CMD ["python3", "main.py"]
