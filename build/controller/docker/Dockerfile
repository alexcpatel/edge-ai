# Docker image for flashing Jetson devices
# This container includes all necessary tools for USB and SD card flashing

FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages for tegraflash
RUN apt-get update -qq && \
    apt-get install -y -qq \
    device-tree-compiler \
    python3 \
    sudo \
    udev \
    usbutils \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Create workspace directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]

