SUMMARY = "Edge AI Container Policy Enforcement"
DESCRIPTION = "Docker wrapper that enforces container signing and mount policies"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://edge-docker \
    file://container-signing.pub \
    file://ecr-url.txt \
    file://daemon.json \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "bash docker cosign"

PKI_DIR = "/data/config/pki"
ECR_DIR = "/data/config/ecr"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/edge-docker ${D}${bindir}/

    # Install PKI config (will be copied to /data on first boot)
    install -d ${D}/etc/edge-ai/container-config
    install -m 0644 ${WORKDIR}/container-signing.pub ${D}/etc/edge-ai/container-config/
    install -m 0644 ${WORKDIR}/ecr-url.txt ${D}/etc/edge-ai/container-config/

    # Docker config - use /data/docker for storage (not tmpfs)
    install -d ${D}${sysconfdir}/docker
    install -m 0644 ${WORKDIR}/daemon.json ${D}${sysconfdir}/docker/
}

FILES:${PN} = " \
    ${bindir}/edge-docker \
    /etc/edge-ai/container-config \
    ${sysconfdir}/docker \
"

