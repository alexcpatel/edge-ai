# Docker image for flashing Jetson devices
# This container includes all necessary tools for USB and SD card flashing

FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages for tegraflash
# Enable multiarch support for 32-bit i386 binaries
RUN dpkg --add-architecture i386 && \
    apt-get update -qq && \
    apt-get install -y -qq \
        device-tree-compiler \
        python3 \
        python3-yaml \
        sudo \
        udev \
        usbutils \
        rsync \
        file \
        libc6-i386 \
        libstdc++6:i386 \
        gawk \
        wget \
        git-core \
        diffstat \
        unzip \
        texinfo \
        gcc-multilib \
        build-essential \
        chrpath \
        socat \
        libsdl1.2-dev \
        xterm \
        zstd \
        gdisk \
        && rm -rf /var/lib/apt/lists/*

# Create workspace directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]

