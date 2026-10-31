#!/system/bin/sh

set -eu

MODDIR=${0%/*}
PATH=/system/bin:/system_ext/bin:/vendor/bin:$MODDIR/bin
log_file=/data/adb/shennong-bootmanager.log
ready_file=/metadata/linux-multiboot/b-slot-ready
ready_token=shennong-linux-b-ready-v1
expected_misc_size=4194304

exec >>"$log_file" 2>&1
echo "$(date): Android return service starting"

attempt=0
while [ "$(getprop sys.boot_completed)" != 1 ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 180 ]; then
        echo "$(date): Android boot did not complete; leaving boot state unchanged"
        exit 1
    fi
    sleep 1
done

[ "$(getprop ro.boot.slot_suffix)" = _a ] || {
    echo "$(date): not running Android slot A; leaving boot state unchanged"
    exit 0
}

ready=$(head -n 1 "$ready_file" 2>/dev/null | tr -d '\r\n' || true)
[ "$ready" = "$ready_token" ] || {
    echo "$(date): Kali slot B is not marked ready; leaving boot state unchanged"
    exit 0
}

bootctl=$MODDIR/bin/bootctl
[ -x "$bootctl" ] || {
    echo "$(date): private bootctl payload is missing"
    exit 2
}

attempt=0
while ! "$bootctl" get-current-slot >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        echo "$(date): Android Boot HAL is unavailable"
        exit 3
    fi
    sleep 1
done

"$bootctl" set-active-boot-slot 1
[ "$("$bootctl" is-slot-bootable 1)" = 1 ] || {
    echo "$(date): slot B is not bootable after selection"
    exit 4
}

misc=/dev/block/by-name/misc
[ -b "$misc" ] || {
    echo "$(date): misc block device is missing"
    exit 5
}
[ "$(blockdev --getsize64 "$misc")" = "$expected_misc_size" ] || {
    echo "$(date): unexpected misc partition size"
    exit 6
}

bcb_tmp=$MODDIR/.boot-recovery-bcb
dd if=/dev/zero of="$bcb_tmp" bs=2048 count=1 2>/dev/null
printf 'boot-recovery' | dd of="$bcb_tmp" bs=1 seek=0 conv=notrunc 2>/dev/null
printf 'recovery\n' | dd of="$bcb_tmp" bs=1 seek=64 conv=notrunc 2>/dev/null
expected_sha256=$(sha256sum "$bcb_tmp" | cut -d ' ' -f 1)
dd if="$bcb_tmp" of="$misc" bs=2048 count=1 2>/dev/null
sync
actual_sha256=$(dd if="$misc" bs=2048 count=1 2>/dev/null | sha256sum | cut -d ' ' -f 1)
[ "$actual_sha256" = "$expected_sha256" ] || {
    echo "$(date): BCB read-back verification failed"
    exit 7
}

echo "$(date): next boot armed for shared multiboot recovery B ($actual_sha256)"
