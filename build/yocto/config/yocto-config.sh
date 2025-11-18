#!/bin/bash
# Yocto Build Configuration
# Edit these values according to your setup

# Yocto Configuration
export YOCTO_BRANCH="scarthgap"
export YOCTO_MACHINE="jetson-orin-nano-devkit"  # Jetson Orin Nano Developer Kit
export YOCTO_IMAGE="core-image-sato-dev"  # or core-image-weston, core-image-base
export YOCTO_DIR="/home/${EC2_USER}/yocto-tegra"
export YOCTO_BUILD_DIR="${YOCTO_DIR}/build"

# Source sync configuration
export REMOTE_SOURCE_DIR="${YOCTO_DIR}/edge-ai"  # Remote directory on EC2 (entire repo)

# Available Jetson machines:
# - jetson-tx1-devkit
# - jetson-tx2-devkit
# - jetson-tx2-devkit-tx2i
# - jetson-tx2-devkit-4gb
# - jetson-agx-xavier-devkit
# - jetson-nano-devkit
# - jetson-nano-devkit-emmc
# - jetson-nano-2gb-devkit
# - jetson-xavier-nx-devkit
# - jetson-xavier-nx-devkit-emmc
# - jetson-xavier-nx-devkit-tx2-nx
# - jetson-agx-orin-devkit
# - jetson-orin-nano-devkit
