#!/usr/bin/env python3
"""Patch the exact PixelOS recovery ramdisk for the multiboot selector."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    data = path.read_text(encoding="utf-8")
    if data.count(old) != 1:
        raise SystemExit(f"unexpected occurrence count in {path}: {old!r}")
    path.write_text(data.replace(old, new), encoding="utf-8")


def patch_props(path: Path) -> None:
    replacements = (
        ("ro.secure=1", "ro.secure=0"),
        ("ro.adb.secure=1", "ro.adb.secure=0"),
        ("ro.debuggable=0", "ro.debuggable=1"),
        ("ro.force.debuggable=0", "ro.force.debuggable=1"),
    )
    data = path.read_text(encoding="utf-8")
    old_counts = tuple(data.count(old) for old, _ in replacements)
    new_counts = tuple(data.count(new) for _, new in replacements)
    expected = (1, 2, 1, 1)
    if old_counts == (0, 0, 0, 0) and new_counts == expected:
        return
    if old_counts != expected or new_counts != (0, 0, 0, 0):
        raise SystemExit(
            f"unexpected recovery property state in {path}: "
            f"old={old_counts}, new={new_counts}"
        )
    for old, new in replacements:
        data = data.replace(old, new)
    data += "\nro.recovery.multiboot=1\nro.recovery.linux_root=/dev/block/by-name/linux_root\n"
    path.write_text(data, encoding="utf-8")


def patch_branding(path: Path) -> None:
    data = path.read_bytes()
    replacements = (
        (b"NWRT Recovery / v0.9", b"Linux MultiBoot v1.8"),
        (b"/tmp/xm14-rec.log", b"/multiboot-ui.log"),
        (b"NWRT Recovery", b"Linux REC v1 "),
        (b"NWRT / OpenWrt", b"Linux / Kali  "),
        (b"NWRT / CPE", b"Linux/Kali"),
        (b"OpenWrt", b"Kali   "),
        (b"NWRT", b"KALI"),
    )
    for old, new in replacements:
        if len(old) != len(new):
            raise SystemExit(f"branding replacement length mismatch: {old!r}")
        data = data.replace(old, new)
    if b"NWRT" in data or b"OpenWrt" in data:
        raise SystemExit("legacy branding remains in selector binary")
    path.write_bytes(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("base_root", type=Path)
    parser.add_argument("selector_binary", type=Path)
    args = parser.parse_args()

    base = args.base_root.resolve()
    init_rc = base / "system/etc/init/hw/init.rc"
    replace_once(init_rc, "service recovery /system/bin/recovery", "service recovery /nwrt/bin/recovery")
    replace_once(
        init_rc,
        "service recovery /nwrt/bin/recovery\n"
        "    socket recovery stream 422 system system\n"
        "    seclabel u:r:recovery:s0\n"
        "    user root\n",
        "service recovery /nwrt/bin/recovery\n"
        "    socket recovery stream 422 system system\n"
        "    seclabel u:r:recovery:s0\n"
        "    user root\n"
        "    capabilities SYS_BOOT\n",
    )
    replace_once(
        init_rc,
        "service fastbootd /system/bin/fastbootd\n"
        "    disabled\n"
        "    group system\n"
        "    seclabel u:r:fastbootd:s0\n"
        "    user root\n",
        "service fastbootd /system/bin/fastbootd\n"
        "    disabled\n"
        "    group system\n"
        "    seclabel u:r:fastbootd:s0\n"
        "    user root\n\n"
        "service multiboot-diagnostics /system/bin/sh /nwrt/bin/multiboot-diagnostics\n"
        "    class default\n"
        "    user root\n"
        "    group root shell log\n"
        "    seclabel u:r:recovery:s0\n"
        "    oneshot\n\n"
        "service multiboot-action-bridge /system/bin/sh /nwrt/bin/multiboot-action-bridge\n"
        "    class default\n"
        "    user root\n"
        "    group root shell log\n"
        "    seclabel u:r:recovery:s0\n",
    )
    replace_once(
        init_rc,
        "on boot\n"
        "    ifup lo\n"
        "    hostname localhost\n"
        "    domainname localdomain\n\n"
        "    class_start default\n"
        "    class_start hal\n",
        "on boot\n"
        "    ifup lo\n"
        "    hostname localhost\n"
        "    domainname localdomain\n\n"
        "    # The Qualcomm recovery Boot HAL is class early_hal.\n"
        "    class_start early_hal\n"
        "    class_start default\n"
        "    class_start hal\n"
        "    # Keep diagnostics available without entering sideload mode.\n"
        "    setprop service.adb.root 1\n"
        "    setprop sys.usb.config adb\n",
    )

    patch_props(base / "prop.default")
    patch_props(base / "default.prop")

    contexts = base / "plat_file_contexts"
    context_line = "/nwrt(/.*)?          u:object_r:system_file:s0"
    context_data = contexts.read_text(encoding="utf-8")
    if context_line not in context_data:
        contexts.write_text(context_data.rstrip("\n") + "\n" + context_line + "\n", encoding="utf-8")

    patch_branding(args.selector_binary)


if __name__ == "__main__":
    main()
