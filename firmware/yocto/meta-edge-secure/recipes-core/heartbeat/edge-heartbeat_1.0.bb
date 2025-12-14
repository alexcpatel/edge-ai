SUMMARY = "Edge AI Device Heartbeat Service"
DESCRIPTION = "Periodically updates AWS IoT Device Shadow with device state"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

RDEPENDS:${PN} = "python3-paho-mqtt python3-json"

SRC_URI = " \
    file://edge-heartbeat.py \
    file://edge-heartbeat.service \
"

S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN} = "edge-heartbeat.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/edge-heartbeat.py ${D}${bindir}/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/edge-heartbeat.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    ${bindir}/edge-heartbeat.py \
    ${systemd_system_unitdir}/edge-heartbeat.service \
"

