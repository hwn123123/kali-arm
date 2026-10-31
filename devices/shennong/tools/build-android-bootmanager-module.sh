#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 BOOTCTL OUTPUT_ZIP" >&2
    exit 2
fi

bootctl=$(realpath "$1")
output=$(realpath -m "$2")
source_root=$(realpath "$(dirname "$0")/../android-bootmanager-magisk")
expected_bootctl_sha256=7fa6ca699a0f7845179ac95aa9350fe2a68db81b3eeab769d8665d67e993e885

[ -f "$bootctl" ] || {
    echo "bootctl input is missing: $bootctl" >&2
    exit 3
}
[ "$(sha256sum "$bootctl" | awk '{print $1}')" = "$expected_bootctl_sha256" ] || {
    echo "refusing unverified bootctl input" >&2
    exit 4
}

case "$(file -b "$bootctl")" in
    *ARM\ aarch64*|*ARM64*) ;;
    *) echo "bootctl input is not arm64" >&2; exit 5 ;;
esac

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/shennong-bootmanager.XXXXXX")
cleanup() {
    if [[ "$work_dir" == "${TMPDIR:-/tmp}"/shennong-bootmanager.* && \
          -d "$work_dir" && ! -L "$work_dir" ]]; then
        find "$work_dir" -depth -delete
    fi
}
trap cleanup EXIT

mkdir -p "$work_dir/bin" "$(dirname "$output")"
cp "$source_root/module.prop" "$source_root/service.sh" \
    "$source_root/customize.sh" "$work_dir/"
cp "$bootctl" "$work_dir/bin/bootctl"
chmod 0644 "$work_dir/module.prop"
chmod 0755 "$work_dir/service.sh" "$work_dir/customize.sh" "$work_dir/bin/bootctl"

(
    cd "$work_dir"
    zip -q -9 -r "$output" module.prop service.sh customize.sh bin
)
sha256sum "$output" >"$output.sha256sum"
echo "built=$output"
