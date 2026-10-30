#!/system/bin/sh

set -u

control=/tmp/shennong-maintenance
request=$control/request
status=$control/status
fifo=$control/linux_root.simg
log=/shennong-maintenance.log
root=/dev/block/by-name/linux_root

exec >>"$log" 2>&1

publish() {
    message=$1
    echo "$message" >"$status.tmp"
    chown shell:shell "$status.tmp"
    chmod 0644 "$status.tmp"
    mv -f "$status.tmp" "$status"
    echo "$(date): $message"
}

mkdir -p "$control"
chown shell:shell "$control"
chmod 0770 "$control"
rm -f "$request" "$status" "$fifo"
mkfifo "$fifo"
chown shell:shell "$fifo"
chmod 0660 "$fifo"
publish idle

while true; do
    if [ ! -s "$request" ]; then
        sleep 1
        continue
    fi

    command_line=$(head -n 1 "$request" 2>/dev/null || true)
    rm -f "$request"
    case "$command_line" in
        'flash-linux-root ERASE-LINUX-ROOT')
            publish validating-layout
            if ! /nwrt/bin/linux-rootctl status; then
                publish error-layout-validation
                continue
            fi
            resolved_root=$(readlink -f "$root")
            if grep -qE "(^| )($root|$resolved_root)( |$)" /proc/mounts; then
                publish error-linux-root-mounted
                continue
            fi
            publish waiting-for-sparse-stream
            if ! /nwrt/bin/sparse-write "$fifo" "$root"; then
                publish error-sparse-write
                continue
            fi
            publish checking-ext4
            /system/bin/e2fsck -f -y "$root"
            check_result=$?
            if [ "$check_result" -gt 1 ]; then
                publish error-e2fsck-$check_result
                continue
            fi
            filesystem_type=$(/system/bin/blkid -s TYPE -o value "$root" 2>/dev/null || true)
            filesystem_label=$(/system/bin/blkid -s LABEL -o value "$root" 2>/dev/null || true)
            if [ "$filesystem_type" != ext4 ] || [ "$filesystem_label" != linux_root ]; then
                publish error-filesystem-identity
                continue
            fi
            sync
            publish flash-complete
            ;;
        slot-a)
            if /nwrt/bin/bootctl set-active-boot-slot 0; then
                publish slot-a-selected
            else
                publish error-slot-a
            fi
            ;;
        slot-b)
            if /nwrt/bin/bootctl set-active-boot-slot 1; then
                publish slot-b-selected
            else
                publish error-slot-b
            fi
            ;;
        reboot-fastbootd)
            publish rebooting-fastbootd
            setprop sys.powerctl reboot,fastboot
            ;;
        reboot-bootloader)
            publish rebooting-bootloader
            setprop sys.powerctl reboot,bootloader
            ;;
        reboot-recovery)
            publish rebooting-recovery
            setprop sys.powerctl reboot,recovery
            ;;
        reboot-system)
            publish rebooting-system
            setprop sys.powerctl reboot
            ;;
        status)
            /nwrt/bin/linux-rootctl status || true
            publish idle
            ;;
        *)
            publish error-invalid-request
            ;;
    esac
done
