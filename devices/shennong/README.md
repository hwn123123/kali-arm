# Xiaomi 14 Pro (`shennong`) port

This directory contains the out-of-tree Kali ARM port for the Xiaomi 14 Pro.
Development happens only on the `shennong-6.1` branch of
`hwn123123/kali-arm`. It is not an upstream Kali submission.

## Current native Kali bring-up (2026-11-09)

The maintained early entry point is now `initramfs/boot-shim.c`, derived from
NWRT's proven static PID-1 module/device discovery and recovery dispatch. The
legacy shell init below is a historical input and must not be deployed. The
stock kernel has no `CONFIG_DEVTMPFS`, `CONFIG_FHANDLE` or `CONFIG_SYSVIPC`;
this is an experimental native port, not a fully validated upstream hardware
configuration. A tmpfs plus the small `compat/device-nodes.c` helper supplies
device nodes before the regular udev ownership rules. The helper handles no
firmware requests and runs no second event daemon alongside udev. Kali still owns
systemd, udev, desktop packages and apt; no OpenWrt runtime is used.

Build the current generic ramdisk using the exact tested, private NWRT
`init_boot_b.img` and the current source:

```sh
CC=aarch64-linux-gnu-gcc bash devices/shennong/tools/build-native-init.sh \
  /path/to/tested-nwrt-init_boot_b.img /path/to/magiskboot \
  devices/shennong/out/init_boot_b-kali.img
```

The builder preserves the hash-verified PixelOS first-stage init used only for
REC dispatch. The shared kernel, vendor ramdisk, DTBO and vbmeta remain the
verified stock-compatible NWRT artifacts. They never replace slot A.

The default image uses **Phosh**, a portrait, touch-oriented phone shell, with
Phoc/Wayland, Stevia's on-screen keyboard and the GNOME Console terminal. It
does not use an Android desktop container or an X11-nested mobile shell. For an
offline Kali arm64 root with those packages, seatd, BusyBox static and OpenSSH
installed, apply the maintained profile:

```sh
sudo bash devices/shennong/tools/configure-native-rootfs.sh \
  /path/to/kali-root /path/to/host.pub
```

The profile creates a local `kali` / `123` login (also the lock-screen password),
defaults to Simplified Chinese with CJK fonts and the Asia/Shanghai time zone,
imports the supplied SSH
public key and generates unique SSH host keys on first boot. USB NCM is
`172.31.14.1/24` and does not advertise an Internet gateway. Software display
rendering is selected until the graphics stack is validated. Phoc uses the
working atomic DRM API, excludes the vendor's two virtual displays and sets
the 1440x3200 panel to 60 Hz at scale 3. The vendor panel dimensions are
corrected in the device's Phoc configuration. Automatic
`boot-recovery` arming is disabled.

Deploy only from authenticated REC, using
`tools/install-from-recovery.sh` and a per-deployment payload directory in RAM.
It requires checksums for every payload and every preserved A/REC partition,
checks exact partition sizes, refuses a mounted linux_root, writes a fresh
ext4 root and verifies the B-slot boot files. It does not switch slots or
reboot automatically. Legacy fastboot installation commands below are retained
for history and are not the current installation path.

Verified live on 2026-11-09: native Kali systemd/udev/D-Bus, USB NCM DHCP,
key-based SSH, ADSP battery/Type-C startup, the native Phosh lock screen,
Phoc's panel output and Stevia. The owner confirmed normal touch operation.
The stock kernel has no virtual terminals. `shennong-phosh.service` therefore
uses an unprivileged PAM session on seat0 with the upstream seatd service in
non-VT mode. This also fixes logind brightness/power permissions; no device
nodes are made world-writable to bypass seat management. Device drop-ins skip
Plymouth on this kernel. The underlying GPU acceleration, Wi-Fi, modem/calls,
camera and audio are still separate hardware-porting work; a working mobile
shell is not a claim that the full phone is supported.

The ADSP crash and SPI `Invalid proto 255` errors were traced to an entirely
zero-filled 128 KiB `qupfw_b`. In REC, the valid unchanged A copy was backed up,
copied only to B and read-back checked. The repaired hash is
`21153bd3d941b1215c7613870dcfd6f7d5291d2bf7d15ecb541176fadb249d43`.
Touch and ADSP then started successfully. `shennong-qup-check` remains read-only;
the REC installer repairs only that exact validated blank-B case and rejects
other mismatches before any write.

The device-node helper is compiled for arm64; set `CC` if necessary. The local
`80-drivers.rules` override keeps board drivers under explicit stock module
ordering, after concurrent modalias loads blocked `uevent_show` and
`async_synchronize_cookie`. External-device autoload remains enabled. USB uses
the vendor `mode=peripheral` control and does not wait for ADSP.

XFCE is an optional fallback (`--desktop=xfce`), not the default phone UI.
Its local Xorg modesetting module filters unsupported vendor DRM properties
and guards null atoms, fixing the captured Xorg SIGSEGV. The pinned-source
builder installs only under `/usr/local/lib/xorg-shennong`; Kali's Xorg package
is unchanged. This module is not needed for native Phosh.

## Architecture

The first bootable milestone deliberately keeps the two layers separate:

- Xiaomi's stock OS3.0.308.0 A-slot kernel, DTB/DTBO, early Qualcomm modules
  and firmware interfaces bring up the Snapdragon 8 Gen 3 hardware.
- A native Kali arm64 root filesystem lives on the dedicated GPT partition
  named `linux_root`. Kali owns `/`, systemd, packages and all `apt` sources.
- Proprietary Xiaomi files stay outside the Git repository. They are supplied
  as verified local build inputs and are never copied into Kali's `/usr`.

This means that installing or updating packages remains normal Kali Linux. It
does not turn the Kali root filesystem into an Android chroot.

## Device layout

The current test phone has this verified layout:

| Item | Value |
| --- | --- |
| Android | slot A, preserved and bootable |
| Experimental system | slot B boot chain |
| Linux root partition | `/dev/block/by-name/linux_root` |
| GPT partition | `sda34` at the time of verification |
| Disk logical sector | 4096 bytes |
| Start sector | `76197882` (4096-byte GPT sectors) |
| End sector | `128626681` |
| Size | `52428800` sectors / exactly 200 GiB |
| Filesystem | ext4, expanded to the dedicated 200 GiB partition |
| Recovery | existing REC preserved; not replaced by the native Kali installer |

Never hard-code `sda34` in an installer. Resolve the partition by GPT name
`linux_root` and validate the disk GUID, partition GUID, sector range and exact
byte size before formatting it. The equivalent start and size in 512-byte
units are `609583056` and `419430400`; those are not the GPT sector units
reported by this UFS device. The machine-readable contract is
[`reference/linux-root-layout-v1.json`](reference/linux-root-layout-v1.json).

## Verified private inputs

The reference hashes are in
[`reference/OS3.0.308.0-stock-a.sha256`](reference/OS3.0.308.0-stock-a.sha256).
Only A-slot files are accepted. The saved `vendor_boot_b.img` is known-bad: it
is byte-for-byte identical to `boot_b.img`, so it must never be used.

The locally generated kernel/module bundle is also private. Its kernel is
byte-for-byte identical to the kernel extracted from the verified stock
`boot_a.img`:

```text
Linux 6.1.138-android14-11-g0c3d559bcd85-ab14529422
kernel sha256: 97b2c53022e8c0bd0b279c4c592a196126a6eb0a93647c2957b39dcd5f2dc1c9
bundle sha256: 028bb44b118651ba0ce746f71f3b303f90b21d378719eb606531d5837c9bded1
```

Expected private input locations on the current build server are documented
for convenience, but are not required paths:

```text
/home/ning/xiangmu/shennong-vendor-baseline/OS3.0.308.0
/home/ning/xiangmu/shennong-stable-6.1.138/shennong-kernel-prebuilt-6.1.138.tar.zst
```

They can be checked without modifying them:

```bash
devices/shennong/tools/verify-private-inputs.sh \
  /path/to/OS3.0.308.0 \
  /path/to/shennong-kernel-prebuilt-6.1.138.tar.zst
```

## Historical build stages (superseded)

The instructions in this section describe the earlier shell-init prototype.
Use the native init and REC deployment flow at the top of this document for
the current port. These notes are not instructions to replace the active REC.

The v1.9 recovery keeps the tested graphical multiboot selector and is written
identically to both recovery slots, so the stock slot-A recovery is no longer
exposed as a second management environment.
Volume keys only move the highlight; no action is dispatched until the power
key confirms it.  The power bridge deliberately ignores every selector log
line beginning with `selected` and accepts only the four confirmation-path
messages.  This fixes the v1.6 bug where merely highlighting a reboot item
could execute it.

Before either system is launched, the selector clears only the first 2048-byte
`bootloader_message` structure in `misc`, verifies the cleared bytes, then
switches the slot and reboots.  It never clears the A/B metadata that follows
that structure.  This prevents a stale `boot-recovery` request from sending an
Android-A selection back into recovery A.  Android and Kali each install a
separate next-boot service later in the deployment so successful systems return
to this manager on their following boot.

Build it from the pinned PixelOS recovery, the pinned selector compatibility
image and the recovery assets with:

```bash
devices/shennong/tools/build-multiboot-recovery.sh \
  /path/to/current-a-recovery.img \
  /path/to/xm14pro-nwrt-recovery.img \
  /path/to/recovery-assets \
  devices/shennong/out/recovery-v1.9 \
  /path/to/magiskboot-arm64 \
  /path/to/mkbootimg.py \
  /path/to/avbtool.py \
  devices/shennong/recovery/patch-multiboot-recovery.py
```

The selector input is accepted only at SHA-256
`944cd9b5f64a9c9d4c0f92bec8d355eafe4d67dd72c54f69759ce8414d845460`.
The same verified image is intended for both `recovery_a` and `recovery_b`.
Keep the original recovery-A image as a host-side rollback artifact.

After Kali has written its guarded readiness token, Android A uses the Magisk
module under `android-bootmanager-magisk/` to select slot B and write a verified
`boot-recovery` BCB for the following boot.  The module refuses to change boot
state until Android reports a completed boot and the exact Kali readiness token
exists.  Build it with the private, hash-pinned Android 17 `bootctl` binary:

```bash
devices/shennong/tools/build-android-bootmanager-module.sh \
  /path/to/bootctl-pixelos17 \
  devices/shennong/out/shennong-bootmanager-magisk-v1.zip
```

1. Build the Kali rootfs archive:

   ```bash
   sudo SHENNONG_KERNEL_BUNDLE=/path/to/shennong-kernel-prebuilt-6.1.138.tar.zst \
     ./shennong.sh
   ```

   This builds the Phosh phone image. `--desktop=phosh` is equivalent;
   `--desktop=xfce` selects the optional desktop fallback and `--minimal`
   selects a headless root. The device script selects its extra packages;
   Kali's common desktop-selection code remains unchanged. The artifact is
   written to `images/` as a `tar.zst`, not as a repartitioned phone image.

2. Convert the validated rootfs archive into an Android sparse ext4 image for
   the exact 200 GiB `linux_root` partition:

   ```bash
   sudo devices/shennong/tools/build-linux-root-image.sh \
     images/kali-linux-rolling-shennong-phosh-arm64-rootfs.tar.zst \
     devices/shennong/out/linux_root-kali.simg
   ```

   The builder verifies the rootfs checksum and metadata, constructs the
   filesystem in a temporary sparse file, runs `e2fsck`, converts it with
   `img2simg`, and emits a portable SHA256 file. It never connects to a phone.

   For the guarded recovery installer, build the 8 GiB staging image instead:

   ```bash
   sudo devices/shennong/tools/build-linux-root-staging-image.sh \
     images/kali-linux-rolling-shennong-phosh-arm64-rootfs.tar.zst \
     devices/shennong/out/linux_root-kali-staging.simg
   ```

   The maintenance recovery verifies the 200 GiB target, writes this smaller
   filesystem, checks it, expands ext4 to fill `linux_root`, then checks it
   again. This avoids forcing firmware to zero-fill the entire 200 GiB during
   initial deployment. If the staging image is written directly by fastboot,
   `shennong-expand-rootfs.service` performs the same ext4 growth online during
   the first successful Kali boot after validating the exact 200 GiB device.

3. Build a slot-B `init_boot` image from verified private inputs:

   ```bash
   devices/shennong/tools/build-init-boot.sh \
     /path/to/init_boot_a.img \
     /path/to/arm64/busybox \
     devices/shennong/out/init_boot_b-kali.img
   ```

   Set `MAGISKBOOT=/path/to/magiskboot` when it is not in `PATH`.

4. With the phone already in bootloader fastboot mode, use the guarded host
   installer. The last argument must be a vbmeta image whose AVB flags disable
   both verification and verity:

   ```bash
   devices/shennong/tools/flash-kali-b.sh \
     ERASE-LINUX-ROOT \
     /path/to/verified/OS3.0.308.0-A \
     devices/shennong/out/linux_root-kali-staging.simg \
     devices/shennong/out/init_boot_b-kali.img \
     /path/to/disabled-vbmeta_b.img
   ```

   The installer validates the `shennong` product, unlocked bootloader, exact
   partition sizes, stock input hashes, generated sparse checksum, either the
   guarded 8 GiB staging geometry or full 200 GiB geometry, and AVB flags.
   It writes only `linux_root`, `boot_b`, `vendor_boot_b`, `dtbo_b`,
   `init_boot_b` and `vbmeta_b`, then selects B without rebooting. It contains
   no slot-A, recovery, `userdata`, `super` or wipe operation.

5. The recovery-side guard can inspect the dedicated partition without
   modifying it:

   ```sh
   devices/shennong/recovery/linux-rootctl.sh status
   ```

   Formatting is deliberately gated by the literal destructive token and is
   the only write operation in that tool:

   ```sh
   devices/shennong/recovery/linux-rootctl.sh \
     prepare-ext4 ERASE-LINUX-ROOT
   ```

   The guard refuses to continue unless the exact disk GUID, partition GUID,
   type GUID, sector range and 200 GiB byte size match the recorded device.
   It never writes Android `userdata`, slot A or any boot-chain partition.
   Rootfs deployment and slot-B flashing remain separate release steps and
   must pass their own validation before being added here.

## Bring-up order

The port is intentionally staged so failures remain diagnosable:

1. stock kernel plus stock vendor ramdisk loads the UFS stack;
2. custom initramfs mounts the verified slot-A firmware partitions read-only,
   loads ordered Xiaomi/Qualcomm modules, then mounts `linux_root`;
3. the firmware mounts move into Kali at the paths expected by the stock
   kernel, and the initramfs starts Kali's systemd;
4. the built-in CDC-NCM gadget exposes `172.31.14.1/24`, provides DHCP to the
   USB host and starts key-only SSH for the `kali` user; initramfs, hardware,
   USB-network and systemd-journal logs persist on `linux_root`;
5. keep existing recovery and Android slot A unchanged; do not automatically
   arm recovery or switch slots from a normal Kali boot;
6. display and touch;
7. Wi-Fi/Bluetooth and audio;
8. modem/telephony compatibility bridge;
9. camera compatibility bridge;
10. optional rebuilt kernel features such as namespaces needed by Docker.

Telephony and camera need proprietary Android userspace services in addition
to kernel drivers. They will be isolated under `/opt/shennong-vendor` or in a
sidecar environment instead of being mixed into Kali package directories.
