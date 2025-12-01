# AWS IoT Fleet Provisioning claim certificates
# Baked into rootfs for zero-touch device provisioning
#
# Claim certs are fetched from SSM Parameter Store during EC2 build
# See: firmware/infra/ec2/scripts/on-ec2/run-build.sh

SUMMARY = "AWS IoT Fleet Provisioning claim certificates"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Source from claim-certs directory (populated by run-build.sh from SSM)
FILESEXTRAPATHS:prepend := "${THISDIR}/../../../claim-certs:"

SRC_URI = " \
    file://claim.crt \
    file://claim.key \
    file://config.json \
    file://nordvpn-token \
"

S = "${WORKDIR}"

CLAIM_DIR = "/etc/edge-ai/claim"

do_install() {
    install -d ${D}${CLAIM_DIR}
    install -m 0644 ${WORKDIR}/claim.crt ${D}${CLAIM_DIR}/
    install -m 0600 ${WORKDIR}/claim.key ${D}${CLAIM_DIR}/
    install -m 0644 ${WORKDIR}/config.json ${D}${CLAIM_DIR}/
    install -m 0600 ${WORKDIR}/nordvpn-token ${D}${CLAIM_DIR}/
}

FILES:${PN} = "${CLAIM_DIR}"
