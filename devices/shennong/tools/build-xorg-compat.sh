#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build only the device's modesetting module; never replace a Kali package.
set -euo pipefail
[[ $# == 1 ]] || { echo "usage: $0 ROOT_DIR" >&2; exit 2; }
root=$(realpath "$1")
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $root != / && -x $root/usr/lib/xorg/Xorg ]]
[[ $(uname -m) == aarch64 ]] || {
    echo 'Build this native arm64 display module on the arm64 Ubuntu builder' >&2
    exit 1
}
version=21.1.25
expected=6ad4e3c7b59a309b32c92e5c15ce1267110f9e13f1ac78da62361a628da1a0eb
chroot "$root" /usr/lib/xorg/Xorg -version 2>&1 | grep -F "X Server 1.$version"
for tool in curl tar patch meson ninja pkg-config gcc; do command -v "$tool" >/dev/null; done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
archive=${SHENNONG_XORG_SOURCE_ARCHIVE:-}
if [[ -n $archive ]]; then
    cp "$archive" "$work/xorg.tar.xz"
else
    curl --fail --location --retry 2 \
        "https://www.x.org/releases/individual/xserver/xorg-server-$version.tar.xz" \
        -o "$work/xorg.tar.xz"
fi
[[ $(sha256sum "$work/xorg.tar.xz" | cut -d ' ' -f 1) == "$expected" ]]
tar -xJf "$work/xorg.tar.xz" -C "$work"
source_dir="$work/xorg-server-$version"
patch -d "$source_dir" -p1 < "$here/../compat/xorg-modesetting-properties.patch"
meson setup "$work/build" "$source_dir" \
    -Dxorg=true -Dxvfb=false -Dxnest=false -Dxephyr=false \
    -Dglamor=false -Dglx=false -Ddri1=false -Ddri2=false -Ddri3=false \
    -Dudev=true -Dsystemd_logind=true -Dlibunwind=false \
    -Ddocs=false -Ddevel-docs=false -Dsecure-rpc=false >"$work/configure.log" 2>&1 || {
    cat "$work/configure.log" >&2
    exit 1
}
ninja -C "$work/build" -j"$(nproc)" hw/xfree86/drivers/modesetting/modesetting_drv.so
install -Dm755 "$work/build/hw/xfree86/drivers/modesetting/modesetting_drv.so" \
    "$root/usr/local/lib/xorg-shennong/modules/drivers/modesetting_drv.so"
install -d "$root/usr/local/share/xorg-shennong"
printf 'xorg_version=%s\nsource_sha256=%s\n' "$version" "$expected" > \
    "$root/usr/local/share/xorg-shennong/build-info"
cp "$source_dir/COPYING" "$root/usr/local/share/xorg-shennong/COPYING"
