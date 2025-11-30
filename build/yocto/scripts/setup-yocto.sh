#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Yocto setup script (runs on EC2 instance)
# Assumes Debian/Ubuntu system with apt-get

# Install dependencies
sudo apt-get update -y

# Install required packages
sudo apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc g++ make \
    chrpath socat xterm zstd \
    python3 python3-pip python3-pexpect python3-jinja2 \
    libncurses-dev cpio file \
    patch bzip2 tar perl \
    lz4 libtirpc-dev rpcbind tmux

# Ensure lz4c is available (lz4 package provides lz4, create symlink for lz4c if needed)
# Put symlink in /usr/bin to ensure it's in PATH
if ! command -v lz4c >/dev/null 2>&1; then
    if command -v lz4 >/dev/null 2>&1; then
        # Create symlink from lz4 to lz4c (they're the same tool)
        sudo ln -sf "$(which lz4)" /usr/bin/lz4c
        echo "Created lz4c symlink: /usr/bin/lz4c -> $(which lz4)"
    else
        echo "Error: lz4 not found, cannot create lz4c symlink"
        exit 1
    fi
fi

# Verify required tools are available
for tool in chrpath diffstat lz4c; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: $tool not found in PATH after installation. PATH: $PATH"
        exit 1
    fi
done
echo "All required tools (chrpath, diffstat, lz4c) are available"

# Enable user namespaces for BitBake on Ubuntu 24.04+
# BitBake requires user namespaces which are restricted by default in Ubuntu 24.04
echo "Configuring user namespaces for BitBake..."

# Method 1: Disable AppArmor restriction on unprivileged user namespaces
# This is the key setting for Ubuntu 24.04
if [ -f /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
    current_value=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)
    if [ "$current_value" != "0" ]; then
        echo "Disabling AppArmor restriction on user namespaces (current: $current_value)..."
        echo 0 | sudo tee /proc/sys/kernel/apparmor_restrict_unprivileged_userns >/dev/null
        # Make it persistent
        if ! grep -q "apparmor_restrict_unprivileged_userns" /etc/sysctl.conf 2>/dev/null; then
            echo "kernel.apparmor_restrict_unprivileged_userns=0" | sudo tee -a /etc/sysctl.conf >/dev/null
        fi
    fi
    # Verify it's set
    if [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" = "0" ]; then
        echo "AppArmor user namespace restriction disabled"
    else
        echo "Warning: Failed to disable AppArmor user namespace restriction"
    fi
fi

# Method 2: Enable unprivileged user namespace cloning (if available)
if [ -f /proc/sys/kernel/unprivileged_userns_clone ]; then
    current_value=$(cat /proc/sys/kernel/unprivileged_userns_clone)
    if [ "$current_value" != "1" ]; then
        echo "Enabling kernel.unprivileged_userns_clone (current: $current_value)..."
        sudo sysctl -w kernel.unprivileged_userns_clone=1
        # Make it persistent
        if ! grep -q "kernel.unprivileged_userns_clone" /etc/sysctl.conf 2>/dev/null; then
            echo "kernel.unprivileged_userns_clone=1" | sudo tee -a /etc/sysctl.conf >/dev/null
        fi
    fi
fi

# Install SDL packages
for pkg in libsdl2-dev libsdl1.2-dev; do
    sudo apt-get install -y "$pkg" && break || true
done

# Install Python packages (ensure pip is available first)
if ! python3 -m pip --version >/dev/null 2>&1; then
    echo "pip not found, installing python3-pip..."
    sudo apt-get install -y python3-pip || true
fi

# Install Python packages (use --break-system-packages for Ubuntu 24.04+ externally-managed Python)
# This is safe in our controlled build environment
echo "Installing kas and GitPython..."
python3 -m pip install --user --break-system-packages GitPython kas

# Ensure user's local bin is in PATH (where pip installs --user scripts)
export PATH="$HOME/.local/bin:$PATH"
# Add to bashrc for future sessions
if ! grep -q '\.local/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

# Verify kas is installed and accessible
if ! command -v kas >/dev/null 2>&1; then
    echo "Error: kas command not found after installation. PATH: $PATH"
    exit 1
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
