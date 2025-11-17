#!/bin/bash
# Yocto setup script to run on EC2 instance

set -e

YOCTO_BRANCH="${YOCTO_BRANCH:-scarthgap}"
YOCTO_MACHINE="${YOCTO_MACHINE:-jetson-orin-nano-devkit}"
YOCTO_DIR="${YOCTO_DIR:-/home/$USER/yocto-tegra}"
SSTATE_DIR="${SSTATE_DIR:-/home/$USER/Yocto/sstate_dir}"
DL_DIR="${DL_DIR:-/home/$USER/Yocto/downloads}"

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
    lz4 libtirpc-devel rpcgen perl-core || true

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

# Initialize build
if [ ! -d "build" ]; then
    source poky/oe-init-build-env build

    cat >> conf/local.conf <<EOF
MACHINE ?= "${YOCTO_MACHINE}"
DISTRO_FEATURES = "x11 opengl "
IMAGE_CLASSES += "image_types_tegra"
IMAGE_FSTYPES = "tegraflash"
SSTATE_DIR ?= "${SSTATE_DIR}"
DL_DIR ?= "${DL_DIR}"
BB_NUMBER_THREADS = "4"
PARALLEL_MAKE = "-j4"
EOF

    sed -i '/^BBLAYERS/,/^  " *$/d' conf/bblayers.conf
    cat >> conf/bblayers.conf <<EOF
BBLAYERS ?= " \\
  ${YOCTO_DIR}/meta-tegra \\
  ${YOCTO_DIR}/poky/meta \\
  ${YOCTO_DIR}/poky/meta-poky \\
  ${YOCTO_DIR}/poky/meta-yocto-bsp \\
  "
EOF
else
    cd build
    grep -q "^MACHINE" conf/local.conf && \
        sed -i "s|^MACHINE.*|MACHINE ?= \"${YOCTO_MACHINE}\"|" conf/local.conf || \
        echo "MACHINE ?= \"${YOCTO_MACHINE}\"" >> conf/local.conf

    if ! grep -q "meta-tegra" conf/bblayers.conf; then
        sed -i '/^BBLAYERS/,/^  " *$/d' conf/bblayers.conf
        cat >> conf/bblayers.conf <<EOF
BBLAYERS ?= " \\
  ${YOCTO_DIR}/meta-tegra \\
  ${YOCTO_DIR}/poky/meta \\
  ${YOCTO_DIR}/poky/meta-poky \\
  ${YOCTO_DIR}/poky/meta-yocto-bsp \\
  "
EOF
    fi
fi

mkdir -p "$SSTATE_DIR" "$DL_DIR"

