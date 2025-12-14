# Cosign - Container signing and verification tool from Sigstore
# Downloads prebuilt binary from GitHub releases

SUMMARY = "Container Signing, Verification and Storage in an OCI registry"
HOMEPAGE = "https://github.com/sigstore/cosign"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

PV = "2.4.0"

SRC_URI = "https://github.com/sigstore/cosign/releases/download/v${PV}/cosign-linux-arm64;downloadfilename=cosign"
SRC_URI[sha256sum] = "e9db44c01057395230d0454144c676e7231bff08249620b0170ea19ff201de94"

S = "${WORKDIR}"

# Skip QA checks for prebuilt binary
INSANE_SKIP:${PN} = "already-stripped ldflags"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/cosign ${D}${bindir}/cosign
}

FILES:${PN} = "${bindir}/cosign"

# Only build for aarch64
COMPATIBLE_HOST = "aarch64.*-linux"

