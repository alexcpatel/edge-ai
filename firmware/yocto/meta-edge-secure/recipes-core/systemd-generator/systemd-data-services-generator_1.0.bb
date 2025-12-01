# Systemd generator to load service files from /data/services
# Allows dynamic app installation without rootfs rebuild

SUMMARY = "Systemd generator for /data/services"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://data-services-generator"

S = "${WORKDIR}"

RDEPENDS:${PN} = "bash"

do_install() {
    install -d ${D}${systemd_unitdir}/system-generators
    install -m 0755 ${WORKDIR}/data-services-generator ${D}${systemd_unitdir}/system-generators/
}

FILES:${PN} = "${systemd_unitdir}/system-generators/data-services-generator"

