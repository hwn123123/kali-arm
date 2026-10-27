#!/usr/bin/env bash

set -euo pipefail

expected_init_boot_sha256="d0bb4390db0bcc54014e985743076a01ba896d43d66d1d5921e10cafff3f16da"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
device_dir="$(cd -- "${script_dir}/.." && pwd)"

usage() {
    echo "Usage: $0 STOCK_INIT_BOOT ARM64_BUSYBOX OUTPUT_IMAGE" >&2
    echo "Set MAGISKBOOT=/path/to/magiskboot when it is not in PATH." >&2
    exit 2
}

[ "$#" -eq 3 ] || usage

stock_init_boot="$1"
busybox="$2"
output_image="$3"
magiskboot="${MAGISKBOOT:-$(command -v magiskboot || true)}"

[ -f "$stock_init_boot" ] || {
    echo "Missing stock init_boot image: $stock_init_boot" >&2
    exit 1
}
[ -f "$busybox" ] || {
    echo "Missing static arm64 busybox: $busybox" >&2
    exit 1
}
[ -n "$magiskboot" ] && [ -x "$magiskboot" ] || {
    echo "magiskboot was not found or is not executable" >&2
    exit 1
}

stock_init_boot="$(realpath "$stock_init_boot")"
busybox="$(realpath "$busybox")"
if [[ "$output_image" != /* ]]; then
    output_image="$(pwd)/$output_image"
fi
magiskboot="$(realpath "$magiskboot")"

actual_sha256="$(sha256sum "$stock_init_boot" | awk '{print $1}')"
[ "$actual_sha256" = "$expected_init_boot_sha256" ] || {
    echo "Refusing an unverified init_boot image." >&2
    echo "Expected: $expected_init_boot_sha256" >&2
    echo "Actual:   $actual_sha256" >&2
    exit 1
}

case "$(file -b "$busybox")" in
    *ARM\ aarch64*|*ARM64*) ;;
    *)
        echo "Busybox does not look like an arm64 executable: $busybox" >&2
        exit 1
        ;;
esac

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/shennong-init-boot.XXXXXX")"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

cp -- "$stock_init_boot" "$work_dir/init_boot-stock.img"
cd -- "$work_dir"
"$magiskboot" unpack init_boot-stock.img >/dev/null
[ -f ramdisk.cpio ] || {
    echo "magiskboot did not extract ramdisk.cpio" >&2
    exit 1
}

if "$magiskboot" cpio ramdisk.cpio "exists init" >/dev/null 2>&1; then
    "$magiskboot" cpio ramdisk.cpio "mv init init.android"
fi

"$magiskboot" cpio ramdisk.cpio \
    "mkdir 0755 bin" \
    "add 0755 bin/busybox $busybox" \
    "add 0755 init ${device_dir}/initramfs/init"

mkdir -p -- "$(dirname -- "$output_image")"
"$magiskboot" repack init_boot-stock.img "$output_image" >/dev/null

partition_size="$(stat -c '%s' "$stock_init_boot")"
output_size="$(stat -c '%s' "$output_image")"
[ "$output_size" -le "$partition_size" ] || {
    echo "Generated image is larger than the init_boot partition." >&2
    exit 1
}

output_dir="$(dirname -- "$output_image")"
output_name="$(basename -- "$output_image")"
(
    cd -- "$output_dir"
    sha256sum "$output_name" >"${output_name}.sha256"
)
echo "Created $output_image ($output_size bytes)"
echo "Slot A was not read from or modified by this operation."
