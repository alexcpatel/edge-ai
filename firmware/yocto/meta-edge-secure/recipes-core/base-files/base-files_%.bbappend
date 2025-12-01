# Configure fstab for read-only rootfs with /data as writable partition

do_install:append() {
    # Mount rootfs read-only
    sed -i 's/\(.*\s\/\s.*\)defaults/\1defaults,ro/' ${D}${sysconfdir}/fstab

    # Add /data partition mount (writable)
    echo "" >> ${D}${sysconfdir}/fstab
    echo "# Writable data partition" >> ${D}${sysconfdir}/fstab
    echo "/dev/nvme0n1p2  /data  ext4  defaults,noatime  0  2" >> ${D}${sysconfdir}/fstab

    # Create mount point
    install -d ${D}/data
}
