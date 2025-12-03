# Enable additional drivers for Edge AI
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-jammy-nvidia-tegra:"

SRC_URI += "file://ethernet.cfg"

KERNEL_CONFIG_FRAGMENTS += "${WORKDIR}/ethernet.cfg"

