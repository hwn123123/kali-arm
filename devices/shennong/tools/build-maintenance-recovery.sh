#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 9 ]; then
    echo "usage: $0 BASE_RECOVERY ASSETS OUTPUT_DIR MAGISKBOOT MKBOOTIMG AVBTOOL PATCHER SPARSE_WRITER MAINTENANCE_SCRIPT" >&2
    exit 2
fi

base_recovery="$(realpath "$1")"
assets="$(realpath "$2")"
output_dir="$(realpath -m "$3")"
magiskboot="$(realpath "$4")"
mkbootimg="$(realpath "$5")"
avbtool="$(realpath "$6")"
patcher="$(realpath "$7")"
sparse_writer="$(realpath "$8")"
maintenance_script="$(realpath "$9")"

partition_size=104857600
base_sha256=0d32c95a88f1ff626d40df4fc55071f86943662ccea84c9f165c659483565366
bootctl_sha256=7fa6ca699a0f7845179ac95aa9350fe2a68db81b3eeab769d8665d67e993e885
sgdisk_sha256=a45ce343bc7421e607146bc45a95c2b5e364e74b18dc4a9d29793b11a80b04f5
adb_keys_sha256=740ed6ae14efe79546ed76b7b361d9fb3e36aac1b00e6af24d9699d8f8829f3a
fstab_qcom_sha256=f957f49a52839ec370897a380c3560080c2706bf886596998c131d8ff6a7f6e8
avb_salt=86cae8712927e24be341c381355a4fbb6b319c8117901aeb36b3863c8eccc5da

die() {
    echo "maintenance recovery builder: $*" >&2
    exit 3
}
hash_is() {
    [ -f "$1" ] || die "missing file: $1"
    [ "$(sha256sum "$1" | awk '{print $1}')" = "$2" ] || \
        die "SHA-256 mismatch: $1"
}

for input in "$magiskboot" "$mkbootimg" "$avbtool" "$patcher" \
    "$sparse_writer" "$maintenance_script"; do
    [ -f "$input" ] || die "missing input: $input"
done
hash_is "$base_recovery" "$base_sha256"
hash_is "$assets/bootctl-pixelos17" "$bootctl_sha256"
hash_is "$assets/sgdisk-current" "$sgdisk_sha256"
hash_is "$assets/adb_keys-host.pub" "$adb_keys_sha256"
hash_is "$assets/fstab.qcom" "$fstab_qcom_sha256"

case "$(file -b "$sparse_writer")" in
    *ARM\ aarch64*|*ARM64*) ;;
    *) die "sparse writer is not an arm64 executable" ;;
esac

work_dir="$(mktemp -d /tmp/shennong-maintenance-recovery.XXXXXX)"
cleanup() {
    if [[ "$work_dir" == /tmp/shennong-maintenance-recovery.* && \
          -d "$work_dir" && ! -L "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi
}
trap cleanup EXIT
mkdir -p "$work_dir/base/root" "$work_dir/check" "$output_dir"
find "$output_dir" -mindepth 1 -maxdepth 1 -delete

(
    cd "$work_dir/base"
    "$magiskboot" unpack -n "$base_recovery" >/dev/null
    mv ramdisk.cpio ramdisk.lz4
    "$magiskboot" decompress ramdisk.lz4 ramdisk.cpio >/dev/null
    cd root
    "$magiskboot" cpio ../ramdisk.cpio extract >/dev/null
)

base_root="$work_dir/base/root"
python3 "$patcher" "$base_root"

new_cpio="$work_dir/base/ramdisk.cpio"
"$magiskboot" cpio "$new_cpio" \
    "mkdir 0755 nwrt" \
    "mkdir 0755 nwrt/bin" \
    "add 0755 nwrt/bin/bootctl $assets/bootctl-pixelos17" \
    "add 0755 nwrt/bin/sgdisk $assets/sgdisk-current" \
    "add 0755 nwrt/bin/linux-rootctl $assets/linux-rootctl.sh" \
    "add 0755 nwrt/bin/sparse-write $sparse_writer" \
    "add 0755 nwrt/bin/shennong-maintenance $maintenance_script" \
    "add 0644 fstab.default $assets/fstab.qcom" \
    "add 0644 fstab.qcom $assets/fstab.qcom" \
    "add 0640 adb_keys $assets/adb_keys-host.pub" \
    "add 0644 system/etc/init/hw/init.rc $base_root/system/etc/init/hw/init.rc" \
    "add 0644 prop.default $base_root/prop.default" \
    "add 0644 default.prop $base_root/default.prop" \
    "add 0644 plat_file_contexts $base_root/plat_file_contexts" >/dev/null

for entry in adb_keys fstab.default fstab.qcom nwrt/bin/bootctl \
    nwrt/bin/sgdisk nwrt/bin/linux-rootctl nwrt/bin/sparse-write \
    nwrt/bin/shennong-maintenance; do
    "$magiskboot" cpio "$new_cpio" "exists $entry" >/dev/null || \
        die "missing ramdisk entry: $entry"
done
"$magiskboot" cpio "$new_cpio" test >/dev/null
"$magiskboot" compress=lz4_legacy "$new_cpio" "$work_dir/new-ramdisk.lz4" >/dev/null

raw="$output_dir/shennong-maintenance-recovery-v1.7.raw.img"
image="$output_dir/shennong-maintenance-recovery-v1.7.img"
python3 "$mkbootimg" \
    --header_version 4 \
    --os_version 17.0.0 \
    --os_patch_level 2026-09 \
    --cmdline androidboot.selinux=permissive \
    --ramdisk "$work_dir/new-ramdisk.lz4" \
    --output "$raw"
cp "$raw" "$image"
python3 "$avbtool" add_hash_footer \
    --image "$image" \
    --partition_size "$partition_size" \
    --partition_name recovery \
    --hash_algorithm sha256 \
    --salt "$avb_salt" \
    --algorithm NONE \
    --prop 'com.android.build.recovery.fingerprint:Xiaomi/custom_shennong/shennong:17/CP2A.260605.016/eng.cnmrli:user/release-keys' \
    --append_to_release_string ' shennong-maintenance-recovery-v1.7' >/dev/null
[ "$(stat -c %s "$image")" -eq "$partition_size" ] || \
    die "bad recovery image size"

ln -s "$image" "$work_dir/check/recovery.img"
python3 "$avbtool" verify_image --image "$work_dir/check/recovery.img" >/dev/null
rm "$work_dir/check/recovery.img"

(
    cd "$work_dir/check"
    "$magiskboot" unpack -n "$image" >/dev/null
    mv ramdisk.cpio ramdisk.lz4
    "$magiskboot" decompress ramdisk.lz4 ramdisk.cpio >/dev/null
    "$magiskboot" cpio ramdisk.cpio \
        "extract system/etc/init/hw/init.rc init.rc" \
        "extract nwrt/bin/sparse-write sparse-write" \
        "extract nwrt/bin/shennong-maintenance maintenance" \
        "extract nwrt/bin/linux-rootctl linux-rootctl" >/dev/null
    grep -Fq 'service recovery /system/bin/recovery' init.rc
    grep -Fq 'service shennong-maintenance' init.rc
    grep -Fq 'class_start early_hal' init.rc
    grep -Fq 'flash-linux-root ERASE-LINUX-ROOT' maintenance
    grep -Fq 'expected_partition_guid=C675F892-57A0-4776-A8FD-17C15F0AD78A' linux-rootctl
    cmp sparse-write "$sparse_writer"
    cmp maintenance "$maintenance_script"
)

{
    echo device=shennong
    echo version=1.7
    echo base=current-PixelOS-17-recovery-a
    echo ui=stock-PixelOS-recovery
    echo install_target=recovery_b-only
    echo android_a_recovery_untouched=yes
    echo selinux=permissive-maintenance-environment
    echo adb=shell-with-whitelisted-root-maintenance-broker
    echo linux_root=/dev/block/by-name/linux_root
    echo linux_root_flash=guarded-sparse-fifo
    echo deployment_image_bytes=8589934592
    echo linux_root_bytes=214748364800
    echo recovery_control=/tmp/shennong-maintenance
} >"$output_dir/MANIFEST.txt"
python3 "$avbtool" info_image --image "$image" >"$output_dir/AVB-INFO.txt"
(
    cd "$output_dir"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | \
        sort -z | xargs -0 sha256sum >SHA256SUMS
    sha256sum -c SHA256SUMS
)
echo "built=$image"
