#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Import the private configuration from the working Android vendor dump.
set -euo pipefail
[[ $EUID == 0 && $# == 2 ]] || { echo "usage: sudo $0 ROOT_DIR STOCK_WIFI_CONFIG" >&2; exit 2; }
root=$(realpath "$1")
input=$(realpath "$2")
[[ $root != / && -f $root/etc/shennong-build && -s $input ]]
expected=c675c32b4f0e6cb6379c801297bc8cffc835ce07c9ac3155645844e4d4b3b8d5
[[ $(sha256sum "$input" | cut -d ' ' -f 1) == "$expected" ]] || {
    echo 'Refusing an unknown or modified stock WLAN configuration' >&2; exit 1;
}
install -Dm644 "$input" "$root/usr/lib/firmware/wlan/qca_cld/kiwi_v2/WCNSS_qcom_cfg.ini"
