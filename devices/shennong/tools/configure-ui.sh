#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Select the device UI without changing Kali's shared image builder/packages.
set -euo pipefail
export LC_ALL=C
[[ $EUID == 0 && $# == 1 ]] || { echo "usage: sudo $0 ROOT_DIR" >&2; exit 2; }
root=$(realpath "$1")
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $root != / && -f $root/etc/shennong-build ]]
if [[ -x $root/usr/bin/phosh-session ]]; then
    chroot "$root" glib-compile-schemas --strict /usr/share/glib-2.0/schemas
else
    rm -f "$root/usr/share/glib-2.0/schemas/90-shennong-mobile.gschema.override"
fi
ui=${SHENNONG_UI:-auto}
if [[ $ui == auto ]]; then
    if [[ -x $root/usr/bin/phosh-session ]]; then ui=phosh
    elif [[ -x $root/usr/sbin/lightdm ]]; then ui=xfce
    else ui=none; fi
fi
case "$ui" in
    phosh)
        for binary in usr/bin/phosh-session usr/sbin/seatd usr/bin/phoc; do
            [[ -x $root/$binary ]] || { echo "Missing mobile UI package: $binary" >&2; exit 1; }
        done
        if [[ -n ${SHENNONG_PHOSH_PACKAGE_DIR:-} ]]; then
            package_root=$(realpath "$SHENNONG_PHOSH_PACKAGE_DIR")
            package_revision=0.58.0-1+shennong7
            if [[ -f $package_root/$package_revision/phosh_${package_revision}_arm64.deb ]]; then
                packages=$package_root/$package_revision
            else
                packages=$package_root
            fi
            stage="$root/tmp/shennong-phosh-packages"
            install -d "$stage"
            for name in phosh_0.58.0-1+shennong7_arm64.deb phosh-common_0.58.0-1+shennong7_all.deb \
                phosh-plugins_0.58.0-1+shennong7_arm64.deb; do
                [[ -f $packages/$name ]]
                cp "$packages/$name" "$stage/$name"
            done
            chroot "$root" env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
                /tmp/shennong-phosh-packages/phosh_0.58.0-1+shennong7_arm64.deb \
                /tmp/shennong-phosh-packages/phosh-common_0.58.0-1+shennong7_all.deb \
                /tmp/shennong-phosh-packages/phosh-plugins_0.58.0-1+shennong7_arm64.deb
            rm -rf -- "$stage"
        fi
        chroot "$root" gsettings list-keys mobi.phosh.shell.brightness | grep -qx manual-brightness || {
            echo 'Build the Shennong Phosh packages and supply SHENNONG_PHOSH_PACKAGE_DIR' >&2
            exit 1
        }
        # Migrate older port builds away from forced brightness policy.
        systemctl --root="$root" disable shennong-display-defaults.service 2>/dev/null || true
        rm -f "$root/etc/systemd/system/shennong-display-defaults.service" \
            "$root/usr/local/sbin/shennong-display-defaults"
        chroot "$root" localedef -i en_US -f UTF-8 en_US.UTF-8
        chroot "$root" localedef -i zh_CN -f UTF-8 zh_CN.UTF-8
        chroot "$root" update-locale --reset LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh
        ln -sfn /usr/share/zoneinfo/Asia/Shanghai "$root/etc/localtime"
        printf 'Asia/Shanghai\n' >"$root/etc/timezone"
        systemctl --root="$root" disable lightdm.service phosh.service 2>/dev/null || true
        systemctl --root="$root" enable seatd.service shennong-phosh.service
        systemctl --root="$root" set-default graphical.target
        ;;
    xfce)
        [[ -x $root/usr/sbin/lightdm ]]
        bash "$here/build-xorg-compat.sh" "$root"
        systemctl --root="$root" disable shennong-phosh.service phosh.service 2>/dev/null || true
        systemctl --root="$root" enable lightdm.service
        systemctl --root="$root" set-default graphical.target
        install -d "$root/etc/lightdm/lightdm.conf.d"
        chroot "$root" install -d -m755 -o lightdm -g lightdm /var/lib/lightdm/data
        cat >"$root/etc/lightdm/lightdm.conf.d/50-shennong.conf" <<'EOF'
[Seat:*]
autologin-user=kali
autologin-user-timeout=0
user-session=xfce
xserver-command=X -nolisten tcp -noreset
EOF
        ;;
    none|minimal|slim)
        systemctl --root="$root" disable lightdm.service phosh.service shennong-phosh.service 2>/dev/null || true
        systemctl --root="$root" set-default multi-user.target
        ;;
    *) echo "Unsupported shennong UI: $ui" >&2; exit 2 ;;
esac
printf 'ui=%s\n' "$ui" >"$root/etc/shennong-ui"
