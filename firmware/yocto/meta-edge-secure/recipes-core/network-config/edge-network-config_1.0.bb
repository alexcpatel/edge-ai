# Network configuration for Edge AI devices
# - Default ethernet connection via NetworkManager
# - Mask systemd-networkd services (we use NetworkManager)

SUMMARY = "Edge AI network configuration"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://ethernet-default.nmconnection"

S = "${WORKDIR}"

RDEPENDS:${PN} = "networkmanager"

inherit systemd

do_install() {
    # Install default ethernet connection profile
    # Note: Goes to /data via volatile-binds, but we need initial config
    install -d ${D}${sysconfdir}/NetworkManager/system-connections
    install -m 0600 ${WORKDIR}/ethernet-default.nmconnection \
        ${D}${sysconfdir}/NetworkManager/system-connections/

    # Mask systemd-networkd services (we use NetworkManager instead)
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/systemd-networkd.service
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/systemd-networkd-wait-online.service
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/systemd-networkd.socket

    # Mask the LSB (SysV) network-manager.service to prevent conflict with systemd native service
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/network-manager.service
}

FILES:${PN} = " \
    ${sysconfdir}/NetworkManager/system-connections/ethernet-default.nmconnection \
    ${sysconfdir}/systemd/system/systemd-networkd.service \
    ${sysconfdir}/systemd/system/systemd-networkd-wait-online.service \
    ${sysconfdir}/systemd/system/systemd-networkd.socket \
    ${sysconfdir}/systemd/system/network-manager.service \
"

