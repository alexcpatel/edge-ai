# First-boot bootstrap service for Edge AI devices
# Handles: partition setup, AWS IoT provisioning, NordVPN meshnet, container pulls

SUMMARY = "Edge AI first-boot bootstrap service"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://edge-bootstrap.service \
    file://edge-bootstrap.sh \
    file://edge-provision.sh \
    file://edge-nordvpn.sh \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "edge-bootstrap.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = " \
    bash \
    curl \
    jq \
    openssl \
    docker \
    e2fsprogs-mke2fs \
"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/edge-bootstrap.sh ${D}${bindir}/
    install -m 0755 ${WORKDIR}/edge-provision.sh ${D}${bindir}/
    install -m 0755 ${WORKDIR}/edge-nordvpn.sh ${D}${bindir}/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/edge-bootstrap.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    ${bindir}/edge-bootstrap.sh \
    ${bindir}/edge-provision.sh \
    ${bindir}/edge-nordvpn.sh \
    ${systemd_system_unitdir}/edge-bootstrap.service \
"

