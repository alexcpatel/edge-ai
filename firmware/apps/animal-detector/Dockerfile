FROM nvcr.io/nvidia/deepstream-l4t:6.4-samples

WORKDIR /workspace/app

# Copy application code and bundled config into the image
COPY app/ /workspace/app/

CMD ["bash", "-lc", "python3 main.py"]


