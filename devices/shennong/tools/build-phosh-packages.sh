#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the Shennong Phosh home screen and mobile status bar.
# Run in an arm64 Kali builder with `apt-get build-dep phosh` installed.
set -euo pipefail
[[ $# == 1 ]] || { echo "usage: $0 OUTPUT_DIR" >&2; exit 2; }
[[ $(dpkg --print-architecture) == arm64 ]]
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
out_root=$(realpath -m "$1")
mkdir -p "$out_root"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
version=0.58.0
revision=0.58.0-1+shennong6
out="$out_root/$revision"
mkdir -p "$out"
for component in source debian; do
    if [[ $component == source ]]; then
        archive=${SHENNONG_PHOSH_SOURCE:-}
        url="http://kali.download/kali/pool/main/p/phosh/phosh_${version}.orig.tar.xz"
        expected=b936af34ebed15b29d4f941c48aa328a47da9c2e51cbf6ef89040a90f522ed73
    else
        archive=${SHENNONG_PHOSH_DEBIAN_SOURCE:-}
        url="http://kali.download/kali/pool/main/p/phosh/phosh_${version}-1.debian.tar.xz"
        expected=dc9b725c576ab5462c01119453372bac7b8c15bf5b93f8a8b148d8c69ab29fe7
    fi
    if [[ -n $archive ]]; then cp "$archive" "$work/$component.tar.xz"
    else curl --fail --location --retry 2 "$url" -o "$work/$component.tar.xz"; fi
    [[ $(sha256sum "$work/$component.tar.xz" | cut -d ' ' -f 1) == "$expected" ]]
done
tar -xJf "$work/source.tar.xz" -C "$work"
source_dir="$work/phosh-$version"
tar -xJf "$work/debian.tar.xz" -C "$source_dir"
patch -d "$source_dir" -p1 <"$here/../compat/phosh-manual-brightness.patch"
patch -d "$source_dir" -p1 <"$here/../compat/phosh-native-home.patch"
patch -d "$source_dir" -p1 <"$here/../compat/phosh-phone-home-layout.patch"
patch -d "$source_dir" -p1 <"$here/../compat/phosh-mobile-home-navigation.patch"
{
    printf 'phosh (%s) unstable; urgency=medium\n\n' "$revision"
    printf '  * Move the clock right, enlarge the status bar, use a horizontal battery indicator, and swipe between home and apps.\n'
    printf '  * Keep manual brightness in Phosh GSettings; default to full brightness.\n\n'
    printf ' -- Shennong port maintainers <root@shennong.invalid>  %s\n\n' "$(date -R)"
    cat "$source_dir/debian/changelog"
} >"$source_dir/debian/changelog.new"
mv "$source_dir/debian/changelog.new" "$source_dir/debian/changelog"
(
    cd "$source_dir"
    export DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)"
    export DEB_BUILD_PROFILES='nodoc nocheck'
    dpkg-buildpackage -b -uc -us -Pnodoc,nocheck -j"$(nproc)"
)
cp "$work/phosh_${revision}_arm64.deb" \
   "$work/phosh-common_${revision}_all.deb" \
   "$work/phosh-plugins_${revision}_arm64.deb" "$out/"
(
    cd "$out"
    sha256sum ./*.deb >SHA256SUMS
)
printf 'Built Phosh runtime packages %s in %s\n' "$revision" "$out"
