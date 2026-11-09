#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Run via /nwrt/bin/nwrt-root from an authenticated NWRT REC session.
set -eu
export PATH=/system/bin:/system/xbin:/nwrt/bin
cd /tmp/kali-install
[ -x /nwrt/bin/recovery.selector ]
[ "$(getprop ro.boot.slot_suffix)" = _a ]
[ "$(blockdev --getsize64 /dev/block/by-name/linux_root)" = 214748364800 ]
sha256sum -c PAYLOAD-SHA256SUMS
sha256sum -c PRESERVED-SHA256SUMS
# The bootloader reads QUP microcode from the active slot. A blank qupfw_b
# causes Invalid proto 255 on SPI/I2C and an ADSP QUP_ERR_FATAL reset. The
# runtime firmware bind mounts cannot repair that earlier bootloader input.
for part in qupfw_a qupfw_b; do
    [ "$(blockdev --getsize64 /dev/block/by-name/$part)" = 131072 ]
done
[ "$(od -An -tx1 -N4 /dev/block/by-name/qupfw_a | tr -d ' \n')" = 7f454c46 ]
cmp -s /dev/block/by-name/qupfw_a /dev/block/by-name/qupfw_b || {
    echo 'Refusing install: repair B-slot QUP firmware from the verified working A-slot source in REC first' >&2
    exit 72
}
for part in boot_b init_boot_b vendor_boot_b dtbo_b vbmeta_b; do
    case "$part" in
        boot_b|vendor_boot_b) size=100663296 ;;
        init_boot_b) size=8388608 ;;
        dtbo_b) size=25165824 ;;
        vbmeta_b) size=131072 ;;
        *) exit 70 ;;
    esac
    [ "$(stat -c %s "$part.img")" = "$size" ]
    [ "$(blockdev --getsize64 /dev/block/by-name/$part)" = "$size" ]
done
if grep -q ' /mnt/kali-source ' /proc/mounts; then umount /mnt/kali-source; fi
root_real=$(readlink -f /dev/block/by-name/linux_root)
if grep -E "^($root_real|/dev/block/by-name/linux_root) " /proc/mounts; then
    echo 'linux_root is still mounted; refusing write' >&2
    exit 71
fi
/nwrt/bin/simg2img linux_root-kali.simg /dev/block/by-name/linux_root
sync
mkdir -p /mnt/kali-check
mount -t ext4 /dev/block/by-name/linux_root /mnt/kali-check
grep -qx ID=kali /mnt/kali-check/etc/os-release
[ -f /mnt/kali-check/lib/systemd/systemd ]
[ -f /mnt/kali-check/usr/sbin/sshd ]
[ -f /mnt/kali-check/etc/systemd/system/shennong-devices.service ]
[ -f /mnt/kali-check/home/kali/.ssh/authorized_keys ]
umount /mnt/kali-check
for part in boot_b vendor_boot_b dtbo_b init_boot_b vbmeta_b; do
    expected=$(sha256sum "$part.img" | cut -d ' ' -f 1)
    actual=$(sha256sum "/dev/block/by-name/$part" | cut -d ' ' -f 1)
    if [ "$expected" != "$actual" ]; then
        dd "if=$part.img" "of=/dev/block/by-name/$part" bs=1048576
        sync
        actual=$(sha256sum "/dev/block/by-name/$part" | cut -d ' ' -f 1)
        [ "$actual" = "$expected" ]
    fi
    echo "$part verified: $actual"
done
sha256sum -c PRESERVED-SHA256SUMS
sync
echo 'Kali rootfs and B-slot boot chain verified; no automatic reboot'
