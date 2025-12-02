# First-boot partition setup for /data
# Partition is created at flash time, this formats it as ext4

SUMMARY = "First-boot data partition formatting"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://edge-partition-setup.sh \
    file://edge-partition-setup.service \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "bash e2fsprogs util-linux"

inherit systemd

SYSTEMD_SERVICE:${PN} = "edge-partition-setup.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/edge-partition-setup.sh ${D}${bindir}/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/edge-partition-setup.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    ${bindir}/edge-partition-setup.sh \
    ${systemd_system_unitdir}/edge-partition-setup.service \
"

