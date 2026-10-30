#!/system/bin/sh
set -u

ui_log=/multiboot-ui.log
bridge_log=/multiboot-power.log
state_dir=/tmp/multiboot-action-bridge
mkdir -p "$state_dir"

request_power_action() {
    action=$1
    marker=$2
    [ ! -e "$state_dir/$marker" ] || return 0
    touch "$state_dir/$marker"
    echo "$(date): request $action from $marker" >>"$bridge_log"
    sync
    if ! setprop sys.powerctl "$action"; then
        echo "$(date): setprop failed for $action" >>"$bridge_log"
    fi
}

while true; do
    if [ -r "$ui_log" ]; then
        # The selector logs "selected ..." whenever the highlight moves.  Those
        # lines are navigation state, not confirmation, and must never trigger
        # an action.  The four messages below are emitted only from the power
        # key confirmation path immediately before the selector's reboot call.
        grep -Fq "power off device" "$ui_log" && request_power_action shutdown poweroff
        grep -Fq "reboot to current default system" "$ui_log" && request_power_action reboot reboot-system
        grep -Fq "reboot to recovery" "$ui_log" && request_power_action reboot,recovery reboot-recovery
        grep -Fq "reboot to bootloader" "$ui_log" && request_power_action reboot,bootloader reboot-bootloader
    fi
    sleep 1
done
