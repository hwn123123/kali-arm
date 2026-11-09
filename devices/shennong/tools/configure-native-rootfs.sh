#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Apply only shennong compatibility configuration to an offline Kali root.
set -euo pipefail
export LC_ALL=C
[[ $EUID == 0 && $# == 2 ]] || { echo "usage: sudo $0 ROOT_DIR SSH_PUBLIC_KEY" >&2; exit 2; }
root=$(realpath "$1")
key=$(realpath "$2")
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $root != / && -f $root/etc/shennong-build && -s $key ]]
grep -qx 'device=shennong' "$root/etc/shennong-build"
for path in "$root" "$root/etc" "$root/usr" "$root/var"; do
    chown 0:0 "$path"
    chmod 0755 "$path"
done
cp -a --no-preserve=ownership "$here/../rootfs-overlay/." "$root/"
chmod 755 "$root/usr/local/sbin/"shennong-*
bash "$here/build-native-helpers.sh" "$root"
if [[ -n ${SHENNONG_WIFI_CONFIG:-} ]]; then
    bash "$here/install-wifi-config.sh" "$root" "$SHENNONG_WIFI_CONFIG"
fi
if [[ -s $root/usr/lib/firmware/wlan/qca_cld/kiwi_v2/WCNSS_qcom_cfg.ini ]]; then
    systemctl --root="$root" enable shennong-wifi.service
else
    systemctl --root="$root" disable shennong-wifi.service 2>/dev/null || true
    echo 'Wi-Fi disabled: supply the private input SHENNONG_WIFI_CONFIG' >&2
fi
chroot "$root" usermod -aG sudo,input,video,render kali
printf 'kali:123\n' | chroot "$root" chpasswd
uid=$(awk -F: '$1=="kali" { print $3 }' "$root/etc/passwd")
gid=$(awk -F: '$1=="kali" { print $4 }' "$root/etc/passwd")
# Seeded desktop files from an offline root build must belong to the login
# user; root-owned .config prevents xfconfd and the session from starting.
chown -R "$uid:$gid" "$root/home/kali"
install -d -m700 -o "$uid" -g "$gid" "$root/home/kali/.ssh"
install -m600 -o "$uid" -g "$gid" "$key" "$root/home/kali/.ssh/authorized_keys"
systemctl --root="$root" enable shennong-devices.service shennong-hardware.service shennong-touch.service \
    shennong-adsp.service shennong-usb-network.service shennong-expand-rootfs.service \
    shennong-ssh-hostkeys.service ssh.service
# No automatic slot switch or boot-recovery request from a healthy Kali boot.
systemctl --root="$root" disable shennong-arm-next-recovery.service rpi-resizerootfs.service || true
bash "$here/configure-ui.sh" "$root"
rm -f "$root/var/lib/shennong/rootfs-expanded-v1"
rm -f "$root/var/lib/shennong/next-recovery-armed"
printf 'Native Kali compatibility configured in %s\n' "$root"
