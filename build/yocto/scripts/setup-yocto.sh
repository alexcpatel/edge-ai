#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Yocto setup script (runs on EC2 instance)

# Install dependencies
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
else
    PKG_MGR="yum"
fi

sudo $PKG_MGR update -y
sudo $PKG_MGR install -y \
    gawk wget git diffstat unzip texinfo gcc gcc-c++ make \
    chrpath socat xterm zstd \
    python3 python3-pip python3-pexpect python3-jinja2 \
    ncurses-devel ncurses-compat-libs cpio file \
    which patch bzip2 tar perl-Thread-Queue perl-FindBin \
    lz4 libtirpc-devel rpcgen perl-core tmux || true

for pkg in SDL2-devel SDL-devel libSDL2-devel; do
    $PKG_MGR list available "$pkg" &>/dev/null && sudo $PKG_MGR install -y "$pkg" && break
done

sudo pip3 install GitPython || true

# Setup Yocto
mkdir -p "$YOCTO_DIR"
cd "$YOCTO_DIR"

[ ! -d "poky" ] && git clone -b "${YOCTO_BRANCH}" git://git.yoctoproject.org/poky.git poky || \
    (cd poky && git fetch && git checkout "${YOCTO_BRANCH}" && git pull)

[ ! -d "meta-tegra" ] && git clone -b "${YOCTO_BRANCH}" https://github.com/OE4T/meta-tegra.git || \
    (cd meta-tegra && git fetch && git checkout "${YOCTO_BRANCH}" && git pull)

# Initialize build directory
if [ ! -d "build" ]; then
    source poky/oe-init-build-env build
else
    cd build
fi

# Copy config files with variable substitution
CONFIG_DIR="${YOCTO_DIR}/config"
envsubst < "$CONFIG_DIR/local.conf" > conf/local.conf
envsubst < "$CONFIG_DIR/bblayers.conf" > conf/bblayers.conf

mkdir -p "$SSTATE_DIR" "$DL_DIR"

