#!/usr/bin/env bash
#
# Kali Linux ARM rootfs build script for Xiaomi 14 Pro (shennong).
# The phone boot chain is built separately from verified stock A-slot inputs.
#

set -e

hw_model=${hw_model:-"shennong"}
architecture=${architecture:-"arm64"}
desktop=${desktop:-"xfce"}
hostname=${hostname:-"kali-shennong"}
extra_custom_pkgs="busybox-static file kmod usbutils libdrm2 ${extra_custom_pkgs:-}"

source ./common.d/base_image.sh

basic_network

status "Install shennong rootfs overlay"
# mmdebstrap uses the pre-created host directory as the rootfs mount point.
# Normalize its owner so the resulting archive never records `/` as the
# unprivileged build user.
chown 0:0 "${work_dir}"
# Preserve file modes and links, but never copy the checkout owner's UID/GID
# onto security-sensitive rootfs directories such as /etc and /usr.
cp -a --no-preserve=ownership devices/shennong/rootfs-overlay/. "${work_dir}/"
chmod 0755 "${work_dir}/usr/local/sbin/shennong-hardware-init"
chmod 0644 "${work_dir}/etc/systemd/system/shennong-hardware.service"

for root_owned_path in "${work_dir}" "${work_dir}/etc" "${work_dir}/usr" "${work_dir}/var"; do
    chown 0:0 "$root_owned_path"
    chmod 0755 "$root_owned_path"
    root_metadata="$(stat -c '%u:%g %a' "$root_owned_path")"
    [ "$root_metadata" = "0:0 755" ] || {
        log "Unsafe rootfs metadata on ${root_owned_path}: ${root_metadata}" red
        exit 1
    }
done

cat <<'EOF' >>"${work_dir}/third-stage"
status_stage3 'Configure shennong services'
systemctl disable rpi-resizerootfs.service || true
systemctl enable NetworkManager.service
systemctl enable ssh.service
systemctl enable shennong-hardware.service

if ! id kali >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --groups sudo kali
fi
passwd --lock kali
install -d -m700 -o kali -g kali /home/kali/.ssh
install -d -m755 /opt/shennong-vendor

cat >/etc/sudoers.d/90-shennong-lab <<'SUDOERS'
kali ALL=(ALL:ALL) NOPASSWD: ALL
SUDOERS
chmod 0440 /etc/sudoers.d/90-shennong-lab
EOF

include third_stage

if [ -n "${SHENNONG_AUTHORIZED_KEY_FILE:-}" ]; then
    [ -f "$SHENNONG_AUTHORIZED_KEY_FILE" ] || {
        log "SSH public key file does not exist: $SHENNONG_AUTHORIZED_KEY_FILE" red
        exit 1
    }
    install -m600 "$SHENNONG_AUTHORIZED_KEY_FILE" \
        "${work_dir}/home/kali/.ssh/authorized_keys"
    kali_uid="$(awk -F: '$1 == "kali" { print $3 }' "${work_dir}/etc/passwd")"
    kali_gid="$(awk -F: '$1 == "kali" { print $4 }' "${work_dir}/etc/passwd")"
    chown "${kali_uid}:${kali_gid}" \
        "${work_dir}/home/kali/.ssh/authorized_keys"
fi

kernel_release="6.1.138-android14-11-g0c3d559bcd85-ab14529422"
expected_bundle_sha256="028bb44b118651ba0ce746f71f3b303f90b21d378719eb606531d5837c9bded1"

if [ -n "${SHENNONG_KERNEL_BUNDLE:-}" ]; then
    [ -f "$SHENNONG_KERNEL_BUNDLE" ] || {
        log "Kernel bundle does not exist: $SHENNONG_KERNEL_BUNDLE" red
        exit 1
    }
    actual_bundle_sha256="$(sha256sum "$SHENNONG_KERNEL_BUNDLE" | awk '{print $1}')"
    [ "$actual_bundle_sha256" = "$expected_bundle_sha256" ] || {
        log "Refusing an unverified shennong kernel bundle" red
        exit 1
    }

    status "Install verified Xiaomi 6.1.138 modules"
    module_stage="$(mktemp -d "${TMPDIR:-/tmp}/shennong-modules.XXXXXX")"
    tar --zstd -xf "$SHENNONG_KERNEL_BUNDLE" -C "$module_stage"
    module_root="${work_dir}/lib/modules/${kernel_release}"
    mkdir -p "$module_root/extra/vendor_boot" "$module_root/extra/vendor_dlkm"
    cp -a "$module_stage/staging/modules/system_dlkm/${kernel_release}/." "$module_root/"
    cp -a "$module_stage/staging/modules/vendor_boot/." "$module_root/extra/vendor_boot/"
    cp -a "$module_stage/staging/modules/vendor_dlkm/." "$module_root/extra/vendor_dlkm/"
    chown -R 0:0 "$module_root"
    find "$module_root" -maxdepth 3 -type f \
        \( -name 'modules.load' -o -name 'modules.blocklist' -o -name 'modules.dep' \
        -o -name 'modules.alias' -o -name 'modules.softdep' \) -delete
    depmod -b "$work_dir" "$kernel_release"
    if find "$module_root" \( ! -user root -o ! -group root \) -print -quit | grep -q .; then
        log "Refusing kernel modules with non-root ownership" red
        exit 1
    fi
    rm -rf "$module_stage"
else
    log "SHENNONG_KERNEL_BUNDLE is unset; artifact is rootfs-only and not flash-ready" yellow
fi

cat >"${work_dir}/etc/fstab" <<'EOF'
# linux_root is mounted by the slot-B initramfs before systemd starts.
proc  /proc  proc  defaults  0  0
EOF

git_revision="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
cat >"${work_dir}/etc/shennong-build" <<EOF
device=shennong
git_revision=${git_revision}
kernel_release=${kernel_release}
stock_release=OS3.0.308.0.WNBCNXM
root_partition=linux_root
EOF

include clean_system

status "Validate shennong rootfs metadata"
validate_metadata() {
    local path="$1"
    local expected="$2"
    local actual
    actual="$(stat -c '%u:%g %a' "$path")"
    [ "$actual" = "$expected" ] || {
        log "Unsafe rootfs metadata on ${path}: ${actual}; expected ${expected}" red
        exit 1
    }
}

validate_metadata "${work_dir}" "0:0 755"
validate_metadata "${work_dir}/etc" "0:0 755"
validate_metadata "${work_dir}/usr" "0:0 755"
validate_metadata "${work_dir}/var" "0:0 755"
validate_metadata "${work_dir}/etc/fstab" "0:0 644"
validate_metadata "${work_dir}/etc/systemd/system/shennong-hardware.service" "0:0 644"
validate_metadata "${work_dir}/usr/local/sbin/shennong-hardware-init" "0:0 755"
if [ -n "${SHENNONG_AUTHORIZED_KEY_FILE:-}" ]; then
    validate_metadata "${work_dir}/home/kali/.ssh/authorized_keys" \
        "${kali_uid}:${kali_gid} 600"
fi

status "Create shennong Kali rootfs archive"
mkdir -p "$image_dir"
rootfs_archive="${image_dir}/${image_name}-rootfs.tar.zst"
tar --numeric-owner --xattrs --acls --one-file-system -C "$work_dir" -cpf - . | \
    zstd -T0 -19 -f -o "$rootfs_archive"
rootfs_archive_name="$(basename "$rootfs_archive")"
(
    cd "$image_dir"
    sha256sum "$rootfs_archive_name" >"${rootfs_archive_name}.sha256sum"
)
chmod 0644 "$rootfs_archive" "$rootfs_archive.sha256sum"

log "Your shennong rootfs is: $rootfs_archive" bold
