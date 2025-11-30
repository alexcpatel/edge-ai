#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Install system packages
sudo apt-get update -y
sudo apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc g++ make \
    chrpath socat xterm zstd python3 python3-pip python3-pexpect python3-jinja2 \
    libncurses-dev cpio file patch bzip2 tar perl lz4 libtirpc-dev rpcbind tmux curl

# Install AWS CLI
if ! command -v aws >/dev/null 2>&1; then
    echo "Installing AWS CLI..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q -o /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install --update
    rm -rf /tmp/awscliv2.zip /tmp/aws
fi
command -v aws >/dev/null && echo "AWS CLI: $(aws --version)" || echo "Warning: AWS CLI not installed"

# Create lz4c symlink if needed
if ! command -v lz4c >/dev/null 2>&1 && command -v lz4 >/dev/null 2>&1; then
    sudo ln -sf "$(which lz4)" /usr/bin/lz4c
fi

# Verify tools
for tool in chrpath diffstat lz4c; do
    command -v "$tool" >/dev/null || { echo "Error: $tool not found"; exit 1; }
done

# Enable user namespaces for BitBake (Ubuntu 24.04+)
if [ -f /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
    if [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" != "0" ]; then
        echo 0 | sudo tee /proc/sys/kernel/apparmor_restrict_unprivileged_userns >/dev/null
        grep -q "apparmor_restrict_unprivileged_userns" /etc/sysctl.conf 2>/dev/null || \
            echo "kernel.apparmor_restrict_unprivileged_userns=0" | sudo tee -a /etc/sysctl.conf >/dev/null
    fi
fi

if [ -f /proc/sys/kernel/unprivileged_userns_clone ] && [ "$(cat /proc/sys/kernel/unprivileged_userns_clone)" != "1" ]; then
    sudo sysctl -w kernel.unprivileged_userns_clone=1
    grep -q "unprivileged_userns_clone" /etc/sysctl.conf 2>/dev/null || \
        echo "kernel.unprivileged_userns_clone=1" | sudo tee -a /etc/sysctl.conf >/dev/null
fi

# Install SDL
sudo apt-get install -y libsdl2-dev 2>/dev/null || sudo apt-get install -y libsdl1.2-dev 2>/dev/null || true

# Install Python packages
python3 -m pip install --user --break-system-packages GitPython kas 2>/dev/null || \
    python3 -m pip install --user GitPython kas

# Setup PATH
export PATH="$HOME/.local/bin:$PATH"
grep -q '\.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Verify kas
command -v kas >/dev/null || { echo "Error: kas not found"; exit 1; }

# Setup Yocto directory
mkdir -p "$YOCTO_DIR"
KAS_CONFIG="${REMOTE_SOURCE_DIR}/firmware/yocto/config/kas.yml"
[ -f "$KAS_CONFIG" ] || { echo "Error: kas.yml not found at $KAS_CONFIG"; exit 1; }

echo "Setup complete"
