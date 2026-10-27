#!/system/bin/sh

set -eu

disk=/dev/block/sda
root=/dev/block/by-name/linux_root
sgdisk=${SGDISK:-/nwrt/bin/sgdisk}

expected_disk_guid=0CC9AB68-255D-F5C6-2977-973EF047D32C
expected_partition_guid=C675F892-57A0-4776-A8FD-17C15F0AD78A
expected_type_guid=0FC63DAF-8483-4772-8E79-3D69D8477DE4
expected_start=76197882
expected_end=128626681
expected_bytes=214748364800

fail() {
    echo "linux-rootctl: $*" >&2
    exit 1
}

verify_layout() {
    [ -x "$sgdisk" ] || fail "sgdisk is unavailable: $sgdisk"
    [ -b "$disk" ] || fail "UFS disk is unavailable: $disk"
    [ -b "$root" ] || fail "linux_root is unavailable: $root"

    disk_info="$($sgdisk --print "$disk")" || fail "cannot read GPT"
    partition_info="$($sgdisk --info=34 "$disk")" || \
        fail "cannot read partition 34"

    echo "$disk_info" | grep -F \
        "Disk identifier (GUID): $expected_disk_guid" >/dev/null || \
        fail "disk GUID mismatch"
    echo "$partition_info" | grep -F \
        "Partition unique GUID: $expected_partition_guid" >/dev/null || \
        fail "partition GUID mismatch"
    echo "$partition_info" | grep -F \
        "Partition GUID code: $expected_type_guid" >/dev/null || \
        fail "partition type mismatch"
    echo "$partition_info" | grep -F "First sector: $expected_start " \
        >/dev/null || fail "start sector mismatch"
    echo "$partition_info" | grep -F "Last sector: $expected_end " \
        >/dev/null || fail "end sector mismatch"
    echo "$partition_info" | grep -F "Partition name: 'linux_root'" \
        >/dev/null || fail "partition name mismatch"

    block_name="$(basename "$(readlink -f "$root")")"
    [ -r "/sys/class/block/$block_name/size" ] || \
        fail "cannot read linux_root size"
    sectors_512="$(cat "/sys/class/block/$block_name/size")"
    actual_bytes=$((sectors_512 * 512))
    [ "$actual_bytes" -eq "$expected_bytes" ] || \
        fail "partition byte size mismatch: $actual_bytes"
}

case "${1:-status}" in
    status)
        verify_layout
        "$sgdisk" --info=34 "$disk"
        /system/bin/blkid "$root" 2>/dev/null || true
        ;;
    prepare-ext4)
        [ "${2:-}" = ERASE-LINUX-ROOT ] || {
            echo "usage: $0 prepare-ext4 ERASE-LINUX-ROOT" >&2
            exit 2
        }
        verify_layout
        resolved_root="$(readlink -f "$root")"
        if grep -qE "(^| )($root|$resolved_root)( |$)" /proc/mounts; then
            fail "linux_root is mounted; refusing format"
        fi
        /system/bin/mke2fs -t ext4 -L linux_root -m 0 -I 256 -F "$root"
        /system/bin/e2fsck -f -y "$root"
        filesystem_type="$(/system/bin/blkid -s TYPE -o value "$root")"
        filesystem_label="$(/system/bin/blkid -s LABEL -o value "$root")"
        [ "$filesystem_type" = ext4 ] || fail "ext4 verification failed"
        [ "$filesystem_label" = linux_root ] || fail "label verification failed"
        ;;
    *)
        echo "usage: $0 {status|prepare-ext4 ERASE-LINUX-ROOT}" >&2
        exit 2
        ;;
esac
