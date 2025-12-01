#!/bin/bash
# Yocto Builder Configuration

# AWS
export AWS_REGION="us-east-2"

# EC2 instance
export EC2_INSTANCE_NAME="yocto-builder"
export EC2_USER="ubuntu"

# Yocto build (paths are on EC2)
export YOCTO_MACHINE="jetson-orin-nano-devkit-nvme"
export YOCTO_DIR="/home/${EC2_USER}/yocto-tegra"
