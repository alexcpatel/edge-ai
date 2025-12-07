# Enable Realtek R8169 ethernet driver (RTL8168 on Orin Nano devkit carrier board)
do_configure:append() {
    echo "CONFIG_NET_VENDOR_REALTEK=y" >> ${B}/.config
    echo "CONFIG_R8169=y" >> ${B}/.config
    oe_runmake -C ${S} O=${B} olddefconfig
}

