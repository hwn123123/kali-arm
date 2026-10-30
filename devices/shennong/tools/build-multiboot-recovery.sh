#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 8 ]]; then
    echo "usage: $0 BASE_RECOVERY SELECTOR_RECOVERY RECOVERY_ASSETS OUTPUT_DIR MAGISKBOOT MKBOOTIMG AVBTOOL PATCHER" >&2
    exit 2
fi

BASE_RECOVERY=$(realpath "$1")
SELECTOR_RECOVERY=$(realpath "$2")
ASSETS=$(realpath "$3")
OUTPUT_DIR=$(realpath -m "$4")
MAGISKBOOT=$(realpath "$5")
MKBOOTIMG=$(realpath "$6")
AVBTOOL=$(realpath "$7")
PATCHER=$(realpath "$8")

PARTITION_SIZE=104857600
BASE_SHA256=0d32c95a88f1ff626d40df4fc55071f86943662ccea84c9f165c659483565366
SELECTOR_SHA256=944cd9b5f64a9c9d4c0f92bec8d355eafe4d67dd72c54f69759ce8414d845460
PATCHER_SHA256=f202d016aeb95368dda9a9d1f5b93ca57e0881733fd249e51069ae0e4fb871b6
SLOT_A_SHA256=ec3e8e61009dd08c3568ab29a3c11cfb52dd41571c9452a7266e6f53ebc68d40
SLOT_B_GUARD_SHA256=86c7f4e60a66a310b19783688802a5ad736edc3cdc36c0ff9edcc4f45b17e0ca
BOOTCTL_SHA256=7fa6ca699a0f7845179ac95aa9350fe2a68db81b3eeab769d8665d67e993e885
LINUX_ROOTCTL_SHA256=d71b3e9bbac251ed38dec298831f053848ea0cbb101d3925fd87c0dd8d2499e7
SGDISK_SHA256=a45ce343bc7421e607146bc45a95c2b5e364e74b18dc4a9d29793b11a80b04f5
ADB_KEYS_SHA256=740ed6ae14efe79546ed76b7b361d9fb3e36aac1b00e6af24d9699d8f8829f3a
DIAGNOSTICS_SHA256=372058fa0eb978171f627df80cf9e4504c7972f38b96d814acc3178078cc30df
ACTION_BRIDGE_SHA256=8293b3a6ad9f37bc99aa20053c2093493bc88de904d8add34d353cb91aa4a863
FSTAB_QCOM_SHA256=f957f49a52839ec370897a380c3560080c2706bf886596998c131d8ff6a7f6e8
AVB_SALT=86cae8712927e24be341c381355a4fbb6b319c8117901aeb36b3863c8eccc5da

die() { echo "multiboot recovery builder: $*" >&2; exit 3; }
hash_is() {
    [[ -f "$1" ]] || die "missing file: $1"
    [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || die "SHA-256 mismatch: $1"
}

for tool in "$MAGISKBOOT" "$MKBOOTIMG" "$AVBTOOL" "$PATCHER"; do
    [[ -f "$tool" ]] || die "missing tool: $tool"
done
hash_is "$BASE_RECOVERY" "$BASE_SHA256"
hash_is "$SELECTOR_RECOVERY" "$SELECTOR_SHA256"
hash_is "$PATCHER" "$PATCHER_SHA256"
hash_is "$ASSETS/xm14-slot-a.sh" "$SLOT_A_SHA256"
hash_is "$ASSETS/xm14-slot-b-guard.sh" "$SLOT_B_GUARD_SHA256"
hash_is "$ASSETS/bootctl-pixelos17" "$BOOTCTL_SHA256"
hash_is "$ASSETS/linux-rootctl-v1.8.sh" "$LINUX_ROOTCTL_SHA256"
hash_is "$ASSETS/sgdisk-current" "$SGDISK_SHA256"
hash_is "$ASSETS/adb_keys-host.pub" "$ADB_KEYS_SHA256"
hash_is "$ASSETS/multiboot-diagnostics.sh" "$DIAGNOSTICS_SHA256"
hash_is "$ASSETS/multiboot-action-bridge.sh" "$ACTION_BRIDGE_SHA256"
hash_is "$ASSETS/fstab.qcom" "$FSTAB_QCOM_SHA256"

work_dir=$(mktemp -d /tmp/xm14-multiboot-recovery.XXXXXX)
cleanup() {
    if [[ "$work_dir" == /tmp/xm14-multiboot-recovery.* && -d "$work_dir" && ! -L "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi
}
trap cleanup EXIT
mkdir -p "$work_dir/base/root" "$work_dir/selector/root" "$work_dir/check" "$OUTPUT_DIR"
find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -delete

(
    cd "$work_dir/base"
    "$MAGISKBOOT" unpack -n "$BASE_RECOVERY" >/dev/null
    mv ramdisk.cpio ramdisk.lz4
    "$MAGISKBOOT" decompress ramdisk.lz4 ramdisk.cpio >/dev/null
    cd root
    "$MAGISKBOOT" cpio ../ramdisk.cpio extract >/dev/null
)
(
    cd "$work_dir/selector"
    "$MAGISKBOOT" unpack -n "$SELECTOR_RECOVERY" >/dev/null
    mv ramdisk.cpio ramdisk.lz4
    "$MAGISKBOOT" decompress ramdisk.lz4 ramdisk.cpio >/dev/null
    cd root
    "$MAGISKBOOT" cpio ../ramdisk.cpio extract >/dev/null
)

base_root="$work_dir/base/root"
selector_root="$work_dir/selector/root"
python3 "$PATCHER" "$base_root" "$selector_root/nwrt/bin/recovery"

new_cpio="$work_dir/new-ramdisk.cpio"
cp "$work_dir/base/ramdisk.cpio" "$new_cpio"
while IFS= read -r -d '' path; do
    rel=${path#"$selector_root/"}
    mode=$(stat -c '%a' "$path")
    "$MAGISKBOOT" cpio "$new_cpio" "mkdir $mode $rel" >/dev/null
done < <(find "$selector_root/nwrt" -type d -print0 | sort -z)
while IFS= read -r -d '' path; do
    rel=${path#"$selector_root/"}
    mode=$(stat -c '%a' "$path")
    "$MAGISKBOOT" cpio "$new_cpio" "add $mode $rel $path" >/dev/null
done < <(find "$selector_root/nwrt" -type f -print0 | sort -z)

"$MAGISKBOOT" cpio "$new_cpio" \
    "add 0755 nwrt/bin/recovery.stock $base_root/system/bin/recovery" \
    "add 0755 nwrt/bin/bootctl $ASSETS/bootctl-pixelos17" \
    "add 0755 nwrt/bin/xm14-slot-a $ASSETS/xm14-slot-a.sh" \
    "add 0755 nwrt/bin/xm14-slot-b $ASSETS/xm14-slot-b-guard.sh" \
    "add 0755 nwrt/bin/linux-rootctl $ASSETS/linux-rootctl-v1.8.sh" \
    "add 0755 nwrt/bin/sgdisk $ASSETS/sgdisk-current" \
    "add 0755 nwrt/bin/multiboot-diagnostics $ASSETS/multiboot-diagnostics.sh" \
    "add 0755 nwrt/bin/multiboot-action-bridge $ASSETS/multiboot-action-bridge.sh" \
    "add 0644 fstab.default $ASSETS/fstab.qcom" \
    "add 0644 fstab.qcom $ASSETS/fstab.qcom" \
    "add 0640 adb_keys $ASSETS/adb_keys-host.pub" \
    "add 0644 system/etc/init/hw/init.rc $base_root/system/etc/init/hw/init.rc" \
    "add 0644 prop.default $base_root/prop.default" \
    "add 0644 plat_file_contexts $base_root/plat_file_contexts" >/dev/null

"$MAGISKBOOT" cpio "$new_cpio" test >/dev/null
for entry in adb_keys fstab.default fstab.qcom nwrt/bin/recovery nwrt/bin/recovery.stock nwrt/bin/bootctl nwrt/bin/xm14-slot-a nwrt/bin/xm14-slot-b nwrt/bin/linux-rootctl nwrt/bin/sgdisk nwrt/bin/multiboot-diagnostics nwrt/bin/multiboot-action-bridge; do
    "$MAGISKBOOT" cpio "$new_cpio" "exists $entry" >/dev/null || die "missing ramdisk entry: $entry"
done
"$MAGISKBOOT" compress=lz4_legacy "$new_cpio" "$work_dir/new-ramdisk.lz4" >/dev/null

raw="$OUTPUT_DIR/shennong-multiboot-recovery-v1.8.raw.img"
image="$OUTPUT_DIR/shennong-multiboot-recovery-v1.8.img"
"$MKBOOTIMG" \
    --header_version 4 \
    --os_version 17.0.0 \
    --os_patch_level 2026-09 \
    --ramdisk "$work_dir/new-ramdisk.lz4" \
    --output "$raw"
cp "$raw" "$image"
"$AVBTOOL" add_hash_footer \
    --image "$image" \
    --partition_size "$PARTITION_SIZE" \
    --partition_name recovery \
    --hash_algorithm sha256 \
    --salt "$AVB_SALT" \
    --algorithm NONE \
    --prop 'com.android.build.recovery.fingerprint:Xiaomi/custom_shennong/shennong:17/CP2A.260605.016/eng.cnmrli:user/release-keys' \
    --append_to_release_string ' xm14-multiboot-recovery-v1.8' >/dev/null
[[ "$(stat -c %s "$image")" -eq "$PARTITION_SIZE" ]] || die "bad recovery image size"
ln -s "$image" "$work_dir/check/recovery.img"
"$AVBTOOL" verify_image --image "$work_dir/check/recovery.img" >/dev/null
rm "$work_dir/check/recovery.img"

(
    cd "$work_dir/check"
    "$MAGISKBOOT" unpack -n "$image" >/dev/null
    mv ramdisk.cpio ramdisk.lz4
    "$MAGISKBOOT" decompress ramdisk.lz4 ramdisk.cpio >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract system/etc/init/hw/init.rc init.rc" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract nwrt/bin/recovery selector" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract nwrt/bin/bootctl bootctl" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract nwrt/bin/xm14-slot-a slot-a" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract nwrt/bin/xm14-slot-b slot-b-guard" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract nwrt/bin/recovery.stock recovery.stock" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract nwrt/bin/multiboot-diagnostics multiboot-diagnostics" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract nwrt/bin/multiboot-action-bridge multiboot-action-bridge" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract fstab.default fstab.default" >/dev/null
    "$MAGISKBOOT" cpio ramdisk.cpio "extract fstab.qcom fstab.qcom" >/dev/null
    grep -Fq 'service recovery /nwrt/bin/recovery' init.rc
    grep -Fq 'capabilities SYS_BOOT' init.rc
    grep -Fq 'class_start early_hal' init.rc
    grep -Fq 'setprop sys.usb.config adb' init.rc
    grep -Fq 'service multiboot-diagnostics' init.rc
    grep -Fq 'service multiboot-action-bridge' init.rc
    grep -Fq '/nwrt/bin/bootctl' slot-a
    grep -Fq 'b-slot-ready' slot-b-guard
    cmp bootctl "$ASSETS/bootctl-pixelos17"
    cmp recovery.stock "$base_root/system/bin/recovery"
    cmp multiboot-diagnostics "$ASSETS/multiboot-diagnostics.sh"
    cmp multiboot-action-bridge "$ASSETS/multiboot-action-bridge.sh"
    cmp fstab.default "$ASSETS/fstab.qcom"
    cmp fstab.qcom "$ASSETS/fstab.qcom"
    ! grep -aFq 'NWRT' selector
    grep -aFq 'Linux MultiBoot v1.8' selector
    grep -aFq '/multiboot-ui.log' selector
    ! grep -aFq '/tmp/xm14-rec.log' selector
)

{
    echo "device=shennong"
    echo "version=1.8"
    echo "base=current-PixelOS-17-recovery-a"
    echo "install_target=recovery_b-first"
    echo "android_a_recovery_untouched=yes"
    echo "linux_root=/dev/block/by-name/linux_root"
    echo "slot_b_guard=requires-/metadata/linux-multiboot/b-slot-ready"
    echo "linux_root_format=manual-explicit-token-only"
    echo "adb=diagnostic-root"
    echo "adb_host_key=embedded-current-mac-public-key"
    echo "boot_control=android-17-aidl-bootctl"
    echo "reboot_capability=SYS_BOOT"
    echo "boot_hal_class=early_hal-enabled"
    echo "adb_mode=automatic-root"
    echo "root_fstab_default=present-for-boot-hal"
    echo "root_fstab_qcom=present"
    echo "diagnostics=/linux-multiboot-diagnostics.log"
    echo "selector_log=/multiboot-ui.log"
    echo "power_actions=confirmed-only-init-sys.powerctl-bridge"
} >"$OUTPUT_DIR/MANIFEST.txt"
"$AVBTOOL" info_image --image "$image" >"$OUTPUT_DIR/AVB-INFO.txt"
(
    cd "$OUTPUT_DIR"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS
    sha256sum -c SHA256SUMS
)
echo "built=$image"
