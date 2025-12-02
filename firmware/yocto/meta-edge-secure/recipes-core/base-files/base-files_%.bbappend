# Configure fstab for read-only rootfs with /data as writable partition

do_install:append() {
    # Mount rootfs read-only
    sed -i 's/\(.*\s\/\s.*\)defaults/\1defaults,ro/' ${D}${sysconfdir}/fstab

    # Add /data partition mount (writable)
    # x-systemd.requires ensures partition-setup runs first, nofail allows boot even if mount fails
    # Partition 16 is created at first boot by shrinking APP (partition 1)
    echo "" >> ${D}${sysconfdir}/fstab
    echo "# Writable data partition (created by edge-partition-setup.service at first boot)" >> ${D}${sysconfdir}/fstab
    echo "/dev/nvme0n1p16  /data  ext4  defaults,noatime,nofail,x-systemd.requires=edge-partition-setup.service  0  2" >> ${D}${sysconfdir}/fstab

    # Create mount point
    install -d ${D}/data
}
