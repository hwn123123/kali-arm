#!/usr/bin/env python3
"""Add the guarded shennong maintenance service to PixelOS recovery."""

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
    for old, new in replacements:
        data = data.replace(old, new)
    data += (
        "\nro.recovery.shennong_maintenance=1\n"
        "ro.recovery.linux_root=/dev/block/by-name/linux_root\n"
    )
    path.write_text(data, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("recovery_root", type=Path)
    args = parser.parse_args()

    root = args.recovery_root.resolve()
    init_rc = root / "system/etc/init/hw/init.rc"
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
        "service shennong-maintenance /system/bin/sh /nwrt/bin/shennong-maintenance\n"
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
        "    class_start early_hal\n"
        "    class_start default\n"
        "    class_start hal\n"
        "    setprop service.adb.root 1\n"
        "    setprop sys.usb.config adb\n",
    )

    patch_props(root / "prop.default")
    patch_props(root / "default.prop")

    contexts = root / "plat_file_contexts"
    context_line = "/nwrt(/.*)?          u:object_r:system_file:s0"
    data = contexts.read_text(encoding="utf-8")
    if context_line not in data:
        contexts.write_text(data.rstrip("\n") + "\n" + context_line + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
