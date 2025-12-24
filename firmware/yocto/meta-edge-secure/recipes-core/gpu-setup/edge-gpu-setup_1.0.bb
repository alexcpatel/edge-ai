# GPU and nvidia-container-runtime setup for Tegra
# Wakes up GPU and configures container runtime for CSV mode

SUMMARY = "GPU and container runtime setup for Tegra"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://edge-gpu-setup.sh \
    file://edge-gpu-setup.service \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "bash"

inherit systemd

SYSTEMD_SERVICE:${PN} = "edge-gpu-setup.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/edge-gpu-setup.sh ${D}${bindir}/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/edge-gpu-setup.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    ${bindir}/edge-gpu-setup.sh \
    ${systemd_system_unitdir}/edge-gpu-setup.service \
"
