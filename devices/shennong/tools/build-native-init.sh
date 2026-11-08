#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Reuse the proven NWRT REC dispatch and exact stock vendor boot chain.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $# == 3 ]] || { echo "usage: $0 TESTED_INIT_BOOT MAGISKBOOT OUTPUT" >&2; exit 2; }
base=$(realpath "$1")
magiskboot=$(realpath "$2")
out=$(realpath -m "$3")
expected=bc29086d8c5b762c15dc6de3d889b44a4b1bdbef38aa5c9cb5afe52ace39218a
[[ $(sha256sum "$base" | cut -d ' ' -f 1) == "$expected" ]]
[[ $(stat -c %s "$base") == 8388608 ]]
cc=${CC:-aarch64-linux-gnu-gcc}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
"$cc" -static -O2 -std=c11 -Wall -Wextra -Werror -ffunction-sections \
  -fdata-sections -Wl,--gc-sections -o "$work/kali-init" "$here/../initramfs/boot-shim.c"
file "$work/kali-init" | grep -F 'ARM aarch64'
file "$work/kali-init" | grep -F 'statically linked'
mkdir -p "$(dirname "$out")"
cd "$work"
"$magiskboot" unpack "$base"
"$magiskboot" cpio ramdisk.cpio 'extract android-first-stage-init android-first-stage-init'
[[ $(sha256sum android-first-stage-init | cut -d ' ' -f 1) == 5f2b3f295c45e60668dc596169389a38a198e4693e107e77ab5e705d488f2ac6 ]]
"$magiskboot" cpio ramdisk.cpio "add 0755 init $work/kali-init" 'rm early-splash'
"$magiskboot" repack "$base" "$out"
[[ $(stat -c %s "$out") -le 8388608 ]]
truncate -s 8388608 "$out"
sha256sum "$out" > "$out.sha256"
printf 'Kali init_boot generated: %s\n' "$out"
