# Minimal container-focused image for Edge AI devices
# Immutable rootfs - all apps run in containers on /data partition

SUMMARY = "Edge AI Minimal Container Image"
LICENSE = "MIT"

inherit core-image

# Start from minimal base
IMAGE_INSTALL = " \
    packagegroup-core-boot \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

# Container runtime
IMAGE_INSTALL += " \
    docker \
"

# Networking
IMAGE_INSTALL += " \
    networkmanager \
    edge-network-config \
    wpa-supplicant \
    ca-certificates \
    curl \
    wget \
    chrony \
"

# Bootstrap and provisioning
IMAGE_INSTALL += " \
    edge-partition-setup \
    edge-gpu-setup \
    edge-bootstrap \
    edge-heartbeat \
    edge-claim-certs \
    edge-container-policy \
    systemd-data-services-generator \
    jq \
    openssl \
    python3-paho-mqtt \
    python3-json \
    python3-logging \
"

# System utilities
IMAGE_INSTALL += " \
    bash \
    rsync \
    util-linux \
    e2fsprogs \
    parted \
    volatile-binds \
"

# TPM support (deferred until correct recipes are confirmed)
# IMAGE_INSTALL += " \
#     tpm2-tss \
#     tpm2-tools \
# "

# Debug utilities (remove for production)
IMAGE_INSTALL += " \
    htop \
    less \
    vim \
"

IMAGE_FEATURES += " \
    ssh-server-openssh \
    read-only-rootfs \
"

# Enable debug-tweaks for development (remove for production)
EXTRA_IMAGE_FEATURES += "debug-tweaks"

# Read-only rootfs volatile binds - /data is the only writable partition
VOLATILE_BINDS += " \
    /data/docker /var/lib/docker \
    /data/config/docker /etc/docker \
    /data/config/NetworkManager /var/lib/NetworkManager \
    /data/log /var/log \
"

# Set hostname
hostname:pn-base-files = "edge-ai"

# Image size - keep minimal
IMAGE_ROOTFS_SIZE ?= "2048000"
IMAGE_OVERHEAD_FACTOR = "1.1"

# Note: /data directory structure and .need_provisioning marker are created
# by edge-partition-setup.sh when formatting the data partition at first boot

# Tegraflash output for NVMe
IMAGE_FSTYPES = "tegraflash"

