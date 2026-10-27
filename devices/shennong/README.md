# Xiaomi 14 Pro (`shennong`) port

This directory contains the out-of-tree Kali ARM port for the Xiaomi 14 Pro.
Development happens only on the `shennong-6.1` branch of
`hwn123123/kali-arm`. It is not an upstream Kali submission.

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
| Start sector | `609583056` (512-byte sectors) |
| Size | `419430400` sectors / exactly 200 GiB |
| Filesystem | intentionally unformatted until installation |
| Recovery | custom slot-B multiboot recovery v1.6 |

Never hard-code `sda34` in an installer. Resolve the partition by GPT name
`linux_root` and validate its exact size before formatting it.

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

## Build stages

1. Build the Kali rootfs archive:

   ```bash
   sudo SHENNONG_KERNEL_BUNDLE=/path/to/shennong-kernel-prebuilt-6.1.138.tar.zst \
     ./shennong.sh --minimal
   ```

   Omit `--minimal` for the default XFCE image. The artifact is written to
   `images/` as a `tar.zst`, not as a repartitioned phone image.

2. Build a slot-B `init_boot` image from verified private inputs:

   ```bash
   devices/shennong/tools/build-init-boot.sh \
     /path/to/init_boot_a.img \
     /path/to/arm64/busybox \
     devices/shennong/out/init_boot_b-kali.img
   ```

   Set `MAGISKBOOT=/path/to/magiskboot` when it is not in `PATH`.

3. Installation will be handled by a separate guarded recovery-side tool. It
   must verify `linux_root`, format only that partition, extract the Kali
   rootfs, then write only slot-B boot-chain partitions. No current script in
   this repository formats or flashes the phone.

## Bring-up order

The port is intentionally staged so failures remain diagnosable:

1. stock kernel plus stock vendor ramdisk loads the UFS stack;
2. custom initramfs mounts `linux_root` and starts Kali's systemd;
3. USB/serial or SSH access and persistent logs;
4. display and touch;
5. Wi-Fi/Bluetooth and audio;
6. modem/telephony compatibility bridge;
7. camera compatibility bridge;
8. optional rebuilt kernel features such as namespaces needed by Docker.

Telephony and camera need proprietary Android userspace services in addition
to kernel drivers. They will be isolated under `/opt/shennong-vendor` or in a
sidecar environment instead of being mixed into Kali package directories.
