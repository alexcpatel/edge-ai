#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Mount data volume if not already mounted
setup_data_volume() {
    local mount_point="$YOCTO_DIR"

    # Find the data volume (attached as /dev/sdf, may appear as /dev/nvme1n1)
    local dev=""
    for d in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
        [ -b "$d" ] && { dev="$d"; break; }
    done

    [ -z "$dev" ] && { echo "Data volume not found, using root filesystem"; return 0; }

    # Check if already mounted
    if mountpoint -q "$mount_point" 2>/dev/null; then
        echo "Data volume already mounted at $mount_point"
        return 0
    fi

    # Check if volume has a filesystem
    if ! sudo blkid "$dev" >/dev/null 2>&1; then
        echo "Formatting new data volume..."
        sudo mkfs.ext4 -q "$dev"
    fi

    # Mount the volume
    sudo mkdir -p "$mount_point"
    sudo mount "$dev" "$mount_point"
    sudo chown ubuntu:ubuntu "$mount_point"

    # Add to fstab if not present
    if ! grep -q "$mount_point" /etc/fstab; then
        local uuid=$(sudo blkid -s UUID -o value "$dev")
        echo "UUID=$uuid $mount_point ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    fi

    echo "Data volume mounted at $mount_point"
}

setup_data_volume

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

echo "Setup complete"
