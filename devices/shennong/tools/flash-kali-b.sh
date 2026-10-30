#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  flash-kali-b.sh ERASE-LINUX-ROOT STOCK_A_DIR LINUX_ROOT_SPARSE \
    INIT_BOOT_B_KALI DISABLED_VBMETA_B

This writes only linux_root and slot-B boot-chain partitions. It does not
write slot A, recovery, Android userdata or logical Android system partitions.
The phone must already be in bootloader fastboot mode.
EOF
    exit 2
}

[ "$#" -eq 5 ] || usage
[ "$1" = "ERASE-LINUX-ROOT" ] || {
    echo "Refusing to overwrite linux_root without ERASE-LINUX-ROOT." >&2
    exit 1
}

stock_dir="$2"
linux_root_image="$3"
init_boot_image="$4"
vbmeta_image="$5"

command -v fastboot >/dev/null || {
    echo "fastboot is not available." >&2
    exit 1
}
command -v python3 >/dev/null || {
    echo "python3 is required for image validation." >&2
    exit 1
}

for image in \
    "$stock_dir/boot_a.img" \
    "$stock_dir/vendor_boot_a.img" \
    "$stock_dir/dtbo_a.img" \
    "$linux_root_image" \
    "$init_boot_image" \
    "$vbmeta_image"; do
    [ -f "$image" ] || {
        echo "Missing input: $image" >&2
        exit 1
    }
done

hash_file() {
    if command -v sha256sum >/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

check_hash() {
    image="$1"
    expected="$2"
    actual="$(hash_file "$image")"
    [ "$actual" = "$expected" ] || {
        echo "Hash mismatch for $image" >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 1
    }
}

check_hash "$stock_dir/boot_a.img" \
    1dab6b5799ed7db7e84648e761981b2001e5b5b22dee1fac040a97b2c337e923
check_hash "$stock_dir/vendor_boot_a.img" \
    07ec90a770c41ea5a0a7a03698c26773a15426dcf87fd4b2c4eac350f1ec7acc
check_hash "$stock_dir/dtbo_a.img" \
    2300821865c3dff04c2e25f0ec0cd6bc460c03e1176202ad2b87623a92c6eaf1

python3 - "$linux_root_image" "$init_boot_image" "$vbmeta_image" <<'PY'
import os
import struct
import sys

sparse_path, init_boot_path, vbmeta_path = sys.argv[1:]

with open(sparse_path, "rb") as stream:
    header = stream.read(28)
if len(header) != 28:
    raise SystemExit("linux_root image has a truncated sparse header")
magic, major, minor, file_header, chunk_header, block_size, blocks, chunks, checksum = struct.unpack(
    "<IHHHHIIII", header
)
if magic != 0xED26FF3A or major != 1 or file_header != 28 or chunk_header != 12:
    raise SystemExit("linux_root image is not a supported Android sparse image")
if block_size * blocks != 214_748_364_800:
    raise SystemExit("linux_root sparse image is not exactly 200 GiB logically")

if os.path.getsize(init_boot_path) != 8_388_608:
    raise SystemExit("init_boot image is not exactly 8 MiB")

with open(vbmeta_path, "rb") as stream:
    vbmeta = stream.read(124)
if len(vbmeta) != 124 or vbmeta[:4] != b"AVB0":
    raise SystemExit("vbmeta image does not contain an AVB0 header")
flags = struct.unpack_from(">I", vbmeta, 120)[0]
if flags & 0x3 != 0x3:
    raise SystemExit("vbmeta does not disable both verification and verity")

print(f"Sparse geometry: {block_size} x {blocks} = 200 GiB, {chunks} chunks")
print(f"vbmeta flags: {flags}")
PY

device_list="$(fastboot devices | awk 'NF {print $1}')"
device_count="$(printf '%s\n' "$device_list" | awk 'NF {count++} END {print count + 0}')"
[ "$device_count" -eq 1 ] || {
    echo "Expected exactly one fastboot device, found $device_count." >&2
    exit 1
}

getvar() {
    name="$1"
    fastboot getvar "$name" 2>&1 | \
        sed -nE "s/.*${name}:[[:space:]]*([^[:space:]]+).*/\1/p" | \
        tail -n 1
}

product="$(getvar product)"
[ "$product" = "shennong" ] || {
    echo "Refusing unexpected product: ${product:-unknown}" >&2
    exit 1
}

unlocked="$(getvar unlocked)"
[ "$unlocked" = "yes" ] || [ "$unlocked" = "true" ] || {
    echo "Bootloader does not report an unlocked state." >&2
    exit 1
}

check_partition_size() {
    partition="$1"
    expected="$2"
    raw="$(getvar "partition-size:${partition}")"
    [ -n "$raw" ] || {
        echo "Fastboot did not report the size of $partition." >&2
        exit 1
    }
    actual=$((raw))
    [ "$actual" -eq "$expected" ] || {
        echo "Unexpected size for $partition: $actual (expected $expected)." >&2
        exit 1
    }
}

check_partition_size linux_root 214748364800
check_partition_size boot_b 100663296
check_partition_size init_boot_b 8388608
check_partition_size vendor_boot_b 100663296
check_partition_size dtbo_b 25165824
check_partition_size vbmeta_b 131072

echo "Validated Xiaomi 14 Pro, exact partition sizes and all image guards."
echo "Writing the independent Linux root partition..."
fastboot flash linux_root "$linux_root_image"

echo "Writing only the slot-B boot chain..."
fastboot flash boot_b "$stock_dir/boot_a.img"
fastboot flash vendor_boot_b "$stock_dir/vendor_boot_a.img"
fastboot flash dtbo_b "$stock_dir/dtbo_a.img"
fastboot flash init_boot_b "$init_boot_image"
fastboot flash vbmeta_b "$vbmeta_image"
fastboot set_active b

echo "Kali slot B is installed and selected. The phone remains in fastboot."
echo "Run 'fastboot reboot' when ready to begin the first boot."
