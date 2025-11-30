#!/bin/bash
# AWS/EC2 Configuration
# Edit these values according to your setup

# AWS Configuration
export AWS_REGION="us-east-2"
export EC2_INSTANCE_NAME="yocto-builder"

# EC2 Instance Configuration
export EC2_USER="ubuntu"
# Note: SSH authentication uses EC2 Instance Connect (no private key needed)
