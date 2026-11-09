#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Apply only shennong compatibility configuration to an offline Kali root.
set -euo pipefail
[[ $EUID == 0 && $# == 2 ]] || { echo "usage: sudo $0 ROOT_DIR SSH_PUBLIC_KEY" >&2; exit 2; }
root=$(realpath "$1")
key=$(realpath "$2")
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $root != / && -f $root/etc/shennong-build && -s $key ]]
grep -qx 'device=shennong' "$root/etc/shennong-build"
cp -a --no-preserve=ownership "$here/../rootfs-overlay/." "$root/"
chmod 755 "$root/usr/local/sbin/"shennong-*
bash "$here/build-native-helpers.sh" "$root"
chroot "$root" usermod -aG sudo,input,video,render kali
printf 'kali:kali\n' | chroot "$root" chpasswd
uid=$(awk -F: '$1=="kali" { print $3 }' "$root/etc/passwd")
gid=$(awk -F: '$1=="kali" { print $4 }' "$root/etc/passwd")
install -d -m700 -o "$uid" -g "$gid" "$root/home/kali/.ssh"
install -m600 -o "$uid" -g "$gid" "$key" "$root/home/kali/.ssh/authorized_keys"
systemctl --root="$root" enable shennong-devices.service shennong-hardware.service shennong-touch.service \
    shennong-adsp.service shennong-usb-network.service shennong-expand-rootfs.service \
    shennong-ssh-hostkeys.service ssh.service
# No automatic slot switch or boot-recovery request from a healthy Kali boot.
systemctl --root="$root" disable shennong-arm-next-recovery.service rpi-resizerootfs.service || true
if [ -x "$root/usr/sbin/lightdm" ]; then
    systemctl --root="$root" set-default graphical.target
    systemctl --root="$root" enable lightdm.service
    install -d "$root/etc/lightdm/lightdm.conf.d"
    cat > "$root/etc/lightdm/lightdm.conf.d/50-shennong.conf" <<'EOF'
[Seat:*]
autologin-user=kali
autologin-user-timeout=0
user-session=xfce
xserver-command=X -nolisten tcp -noreset
EOF
else
    systemctl --root="$root" set-default multi-user.target
fi
rm -f "$root/var/lib/shennong/rootfs-expanded-v1"
rm -f "$root/var/lib/shennong/next-recovery-armed"
printf 'Native Kali compatibility configured in %s\n' "$root"
