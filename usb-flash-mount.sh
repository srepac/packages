#!/bin/bash
# Upload your .img or .bin USB flash images to /var/lib/kvmd/msd/images first then run this script after following the 
# ... github cookbook#mass-storage-drives instructions
#
#set -x
mount -o remount,rw /var/lib/kvmd/msd

DRIVES=$( grep -A10 ^otg: /etc/kvmd/override.yaml | grep count | awk '{print $2}' )
if [[ "$DRIVES" == "" ]]; then
        echo "Missing /etc/kvmd/override.yaml otg count entries.  Please see https://github.com/pikvm/pikvm/blob/master/pages/cookbook.md#mass-storage-drives for details"
        exit 1
fi

# check to see if USB images are found; show list of USB flash images if found
cd /var/lib/kvmd/msd/images
if [[ $( ls | egrep -i '.img|.bin' | wc -l ) -lt 1 ]]; then
        echo "No USB flash images found in /var/lib/kvmd/msd/images."
        exit 1
else
        printf "Based on /etc/kvmd/override.yaml, you can mount up to $DRIVES drives.\nNOTE:  You can press CTRL+C anytime to exit script.\n"
        printf "\nList of USB flash images to pick from:\n\n"
        for i in $( ls *.bin *.img *.BIN *.IMG 2> /dev/null ); do
                printf "  %-20s  %s\n" $i $( du -sh $i | awk '{print $1}' )
        done
fi

for (( i=1; i <=$DRIVES ; i++ )); do
        echo
        # Get the name from user
        read -p "Enter USB flash image name to mount in drive [ $i ]:  " FLASH

        # Mount it
        echo "kvmd-otgmsd -i $i  --set-rw 1 --set-image ${FLASH}"
        kvmd-otgmsd -i $i  --set-rw 1 --set-image ${FLASH}
done
cd
