#!/bin/bash
# For use in conjunction with usb-flash-mount.sh; this script will eject all usb-flash drives mounted via terminal
#set -x

DRIVES=$( grep -A10 ^otg: /etc/kvmd/override.yaml | grep count | awk '{print $2}' )
if [[ "$DRIVES" != "" ]]; then
    for (( i=1; i <=$DRIVES ; i++ )); do
        # Eject each additional drive
        echo "kvmd-otgmsd -i $i --eject"
        kvmd-otgmsd -i $i --eject
        echo
    done
else
    echo "/etc/kvmd/override.yaml does not have otg: count: variable set."
fi

# Set the file system back to Read-only
mount -o remount,ro /var/lib/kvmd/msd
