#!/system/bin/sh

set -eu

ui_print '- Installing Xiaomi 14 Pro multiboot return service'
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/bin/bootctl" 0 0 0755
set_perm "$MODPATH/module.prop" 0 0 0644
