# Squirrel Cam - Dev Workflow Commands
# Run on Jetson Orin with NVIDIA runtime

.PHONY: build up down logs test live shell clean help

# Default target
help:
	@echo "Squirrel Cam - DeepStream ML Pipeline"
	@echo ""
	@echo "Usage:"
	@echo "  make build      - Build all containers"
	@echo "  make up         - Start all services"
	@echo "  make down       - Stop all services"
	@echo "  make logs       - Follow logs from all services"
	@echo "  make test       - Run with test video (no Blink)"
	@echo "  make live       - Run with live Blink cameras"
	@echo "  make shell      - Shell into deepstream container"
	@echo "  make clean      - Remove containers and volumes"
	@echo ""
	@echo "First time setup:"
	@echo "  1. Add test video:  cp your-video.mp4 test-videos/test.mp4"
	@echo "  2. Build:           make build"
	@echo "  3. Test:            make test"
	@echo ""
	@echo "For live Blink cameras:"
	@echo "  1. Edit go2rtc/config.yaml with your Blink credentials"
	@echo "  2. Run:             make live"

# Build all containers
build:
	docker compose build

# Start services with test video
test: build
	SOURCE_URI=rtsp://go2rtc:8554/test docker compose up

# Start services with live Blink cameras
live: build
	@if ! grep -q "^  backyard:" go2rtc/config.yaml 2>/dev/null; then \
		echo "Error: Configure Blink cameras in go2rtc/config.yaml first"; \
		exit 1; \
	fi
	SOURCE_URI=rtsp://go2rtc:8554/backyard docker compose up

# Start in background
up: build
	docker compose up -d

# Stop services
down:
	docker compose down

# Follow logs
logs:
	docker compose logs -f

# Logs for specific service
logs-deepstream:
	docker compose logs -f deepstream

logs-go2rtc:
	docker compose logs -f go2rtc

logs-app:
	docker compose logs -f app

# Shell into deepstream container for debugging
shell:
	docker compose exec deepstream /bin/bash

# Shell into go2rtc
shell-go2rtc:
	docker compose exec go2rtc /bin/sh

# View detection stream (requires VLC or similar)
view:
	@echo "Detection stream available at: rtsp://localhost:8555/ds"
	@echo "Open with: vlc rtsp://localhost:8555/ds"

# Download a sample test video
download-test-video:
	@echo "Downloading sample video..."
	curl -L -o test-videos/test.mp4 \
		"http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
	@echo "Downloaded to test-videos/test.mp4"

# Clean up
clean:
	docker compose down -v --rmi local
	rm -rf deepstream/models/*.engine

# Deep clean - remove all build artifacts
clean-all: clean
	docker compose down -v --rmi all
	rm -rf deepstream/models/*

# Check GPU access
check-gpu:
	docker run --rm --runtime=nvidia nvidia/cuda:12.0-base nvidia-smi

# Run detector directly (for debugging)
run-detector:
	docker compose run --rm deepstream python3 detector.py

# Export model to TensorRT (run once on target device)
export-model:
	docker compose run --rm deepstream python3 -c "\
		from ultralytics import YOLO; \
		model = YOLO('yolov8n.pt'); \
		model.export(format='engine', device=0)"
