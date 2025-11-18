#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Yocto setup script (runs on EC2 instance)
# Assumes Debian/Ubuntu system with apt-get

# Install dependencies
sudo apt-get update -y
sudo apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc g++ make \
    chrpath socat xterm zstd \
    python3 python3-pip python3-pexpect python3-jinja2 \
    libncurses-dev libtinfo5 cpio file \
    patch bzip2 tar perl \
    lz4 libtirpc-dev rpcbind tmux awscli || true

# Install SDL packages
for pkg in libsdl2-dev libsdl1.2-dev; do
    sudo apt-get install -y "$pkg" && break || true
done

# Install Python packages (ensure pip is available first)
if ! python3 -m pip --version >/dev/null 2>&1; then
    echo "pip not found, installing python3-pip..."
    sudo apt-get install -y python3-pip || true
fi

# Install Python packages (use python3 -m pip to avoid PATH issues with sudo)
python3 -m pip install --user GitPython kas || true

# Ensure user's local bin is in PATH (where pip installs --user scripts)
export PATH="$HOME/.local/bin:$PATH"
# Add to bashrc for future sessions
if ! grep -q '\.local/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

# Setup Yocto using KAS
mkdir -p "$YOCTO_DIR"
cd "$YOCTO_DIR"

# KAS will handle all layer management and build directory setup
# The kas.yml file should be in the remote source directory
KAS_CONFIG="${REMOTE_SOURCE_DIR}/build/yocto/config/kas.yml"

if [ ! -f "$KAS_CONFIG" ]; then
    echo "Error: kas.yml not found at $KAS_CONFIG"
    exit 1
fi

# KAS will handle everything during build - no setup needed here
# The kas.yml config will be validated when kas build runs
