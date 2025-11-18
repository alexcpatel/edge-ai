#!/bin/bash
# AWS/EC2 Configuration
# Edit these values according to your setup

# AWS Configuration
export AWS_REGION="us-east-2"
export EC2_INSTANCE_NAME="yocto-builder"

# EC2 Instance Configuration
export EC2_USER="ubuntu"
export EC2_SSH_KEY_PATH="${HOME}/.ssh/yocto-builder-keypair.pem"  # Path to your SSH private key
