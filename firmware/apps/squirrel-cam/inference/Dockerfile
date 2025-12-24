# Ultralytics YOLO image for Jetson JetPack 6 (includes PyTorch + CUDA + TensorRT)
FROM ultralytics/ultralytics:latest-jetson-jetpack6

COPY app/ /app/
WORKDIR /app

ENV MODEL_PATH=/models/yolov8n.engine
ENV DETECTION_THRESHOLD=0.5

CMD ["python3", "detector.py"]
