#!/usr/bin/env bash

set -euo pipefail

readonly staging_size_bytes=8589934592

usage() {
    echo "Usage: sudo $0 ROOTFS.tar.zst OUTPUT.simg" >&2
    echo "Creates an 8 GiB staging ext4 image for recovery deployment." >&2
    echo "The recovery expands it to the exact 200 GiB linux_root partition." >&2
    exit 2
}

[ "$#" -eq 2 ] || usage
[ "${EUID:-$(id -u)}" -eq 0 ] || {
    echo "This builder needs root for loop mounting and numeric ownership." >&2
    exit 1
}

rootfs_archive="$(realpath "$1")"
output_image="$2"
[ -f "$rootfs_archive" ] || {
    echo "Rootfs archive does not exist: $rootfs_archive" >&2
    exit 1
}
if [[ "$output_image" != /* ]]; then
    output_image="$(pwd)/$output_image"
fi
[ ! -e "$output_image" ] || {
    echo "Refusing to overwrite existing output: $output_image" >&2
    exit 1
}

for tool in e2fsck img2simg mke2fs mount mountpoint od realpath sha256sum \
    tar truncate umount zstd; do
    command -v "$tool" >/dev/null || {
        echo "Missing required tool: $tool" >&2
        exit 1
    }
done

checksum_file="${rootfs_archive}.sha256sum"
if [ -f "$checksum_file" ]; then
    (
        cd -- "$(dirname -- "$rootfs_archive")"
        sha256sum --check --strict "$(basename -- "$checksum_file")"
    )
fi
zstd -q -t "$rootfs_archive"

build_metadata="$(tar --zstd -xOf "$rootfs_archive" ./etc/shennong-build)"
echo "$build_metadata" | grep -qx 'device=shennong' || {
    echo "Rootfs is not a shennong build." >&2
    exit 1
}
echo "$build_metadata" | grep -qx 'root_partition=linux_root' || {
    echo "Rootfs does not target linux_root." >&2
    exit 1
}

mkdir -p -- "$(dirname -- "$output_image")"
work_dir="$(mktemp -d "${TMPDIR:-/var/tmp}/shennong-staging-image.XXXXXX")"
raw_image="${work_dir}/linux_root-staging.raw"
mount_dir="${work_dir}/mnt"
sparse_image="${work_dir}/linux_root-staging.simg"
mkdir -p "$mount_dir"

cleanup() {
    if mountpoint -q "$mount_dir"; then
        umount "$mount_dir" || true
    fi
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

echo "Creating an 8 GiB staging ext4 filesystem..."
truncate -s "$staging_size_bytes" "$raw_image"
mke2fs -q -t ext4 -F -L linux_root -m 0 -I 256 -N 262144 "$raw_image"

mount -o loop,rw,noatime "$raw_image" "$mount_dir"
tar --zstd --numeric-owner --xattrs --acls -xpf "$rootfs_archive" \
    -C "$mount_dir"
sync "$mount_dir"
umount "$mount_dir"

e2fsck -f -y "$raw_image"
filesystem_bytes="$(stat -c '%s' "$raw_image")"
[ "$filesystem_bytes" -eq "$staging_size_bytes" ] || {
    echo "Unexpected staging image size: $filesystem_bytes" >&2
    exit 1
}

echo "Converting the staging filesystem to Android sparse format..."
img2simg "$raw_image" "$sparse_image"
sparse_magic="$(od -An -tx1 -N4 "$sparse_image" | tr -d ' \n')"
[ "$sparse_magic" = 3aff26ed ] || {
    echo "Android sparse image header verification failed." >&2
    exit 1
}

mv -- "$sparse_image" "$output_image"
chmod 0644 "$output_image"
output_dir="$(dirname -- "$output_image")"
output_name="$(basename -- "$output_image")"
(
    cd -- "$output_dir"
    sha256sum "$output_name" >"${output_name}.sha256sum"
)

echo "Created $output_image"
echo "Staging filesystem: $staging_size_bytes bytes (8 GiB)"
echo "Recovery will expand ext4 to the verified 200 GiB target."
echo "This operation did not connect to or modify a phone."
