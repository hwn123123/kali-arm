#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
[[ $# == 1 ]] || { echo "usage: $0 ROOT_DIR" >&2; exit 2; }
root=$(realpath "$1")
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $root != / && -d $root/etc ]] || exit 2
compiler=${CC:-aarch64-linux-gnu-gcc}
command -v "$compiler" >/dev/null || {
    echo "Missing arm64 compiler: $compiler (set CC for native arm64 builds)" >&2
    exit 1
}
case "$("$compiler" -dumpmachine)" in
    aarch64*) ;;
    *) echo "CC must target aarch64 for this root filesystem" >&2; exit 1 ;;
esac
install -d "$root/usr/local/libexec"
"$compiler" -static -O2 -Wall -Wextra -Werror \
    "$here/../compat/device-nodes.c" -o "$root/usr/local/libexec/shennong-device-nodes"
chmod 755 "$root/usr/local/libexec/shennong-device-nodes"
