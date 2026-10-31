#!/system/bin/sh
set -eu

ready_file=/metadata/linux-multiboot/b-slot-ready
expected=shennong-linux-b-ready-v1
bootctl=/nwrt/bin/bootctl
log=/multiboot-slot.log

exec >>"$log" 2>&1
echo "slot-b: begin"

if [ ! -b /dev/block/by-name/linux_root ]; then
    echo "linux_root is missing; refusing slot B" >&2
    exit 64
fi
ready=$(head -n 1 "$ready_file" 2>/dev/null | tr -d '\r\n' || true)
if [ "$ready" != "$expected" ]; then
    echo "Kali/Linux is not installed; refusing slot B" >&2
    exit 65
fi

if [ ! -x "$bootctl" ]; then
    echo "bootctl is missing; refusing slot B" >&2
    exit 66
fi

attempt=0
while ! "$bootctl" get-current-slot >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        echo "boot HAL is unavailable; refusing slot B" >&2
        exit 67
    fi
    sleep 1
done

"$bootctl" set-active-boot-slot 1
if [ "$("$bootctl" is-slot-bootable 1)" != 1 ]; then
    echo "slot B is not bootable after selection" >&2
    exit 68
fi

sync
echo "slot-b: selected"
if ! /nwrt/bin/xm14-clear-recovery-request; then
    echo "slot-b: failed to clear recovery request" >&2
    exit 69
fi
setprop sys.powerctl reboot
echo "slot-b: reboot request returned unexpectedly"
sleep 5
exit 70
