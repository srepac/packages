#!/bin/bash
# By @srepac to have the ability to switch between usb dongle and csi bridge (and vice versa) on the same pi
#
# Pre-requisites:
#
#  0. Have both CSI and USB dongle connected to Pi4 so you can switch between them
#  1. config.txt.usb            file in the same directory as this script (main diff is no dtoverlay=tc358743)
#  2. config.txt.csi            file in the same directory as this script
#  3. /etc/kvmd/override.yaml   contains the following (without the beginning #):
: '
### makes it seamless to switch between the capture cards.. you only have to move HDMI cable to get video
kvmd:
    streamer:
        forever: true
        cmd_append: [--slowdown]                    # for usb-hdmi only so that target PC display works w/o rebooting
        h264_bitrate:
            default: 5000
        cmd_append:
            - "--h264-sink=kvmd::ustreamer::h264"   # needed in order to capture video
            - "--h264-sink-mode=0660"
            - "--h264-bitrate={h264_bitrate}"
            - "--h264-gop={h264_gop}"
'
###
# Overview steps the script performs
# 0.  backup custom edid file
# 1.  show current platform and ask to switch to another (i.e from CSI to USB and vice versa)
# 2.  copy relevant /boot/config.txt
BOOTCONFIG="/boot/config.txt"
#
###
# HISTORY:
#
#  07/08/21  srepac     created script per @mh166 request and @Arch1mede hounding me
#                       ... tested manual commands and worked as expected
#  07/09/21  srepac     added ability to change from USB to CSI V2 or V3 HAT, and make sure script only works on Pi4
#  07/10/21  srepac     Due to kvmd services, web portal make take up to 2 mins before it responds after pi reboots
#                       ... this is especially true if switching from CSI to USB
#  07/28/21  srepac     v1.1 buxfix: enable tc358743.service when switching from USB to CSI
#  07/30/21  srepac     v1.2 slight edit of bugfix above after testing going from USB -> CSI platform
#
VER="1.2"
printf "KVMD-PLATFORM SWITCHER v$VER by srepac\n\n"

# Script only works on Pi 4
MODEL=`awk '{print $3}' /proc/device-tree/model`
if [[ "$MODEL" != "4" ]]; then
        printf "Script only works on Pi 4.  You are running this from a Pi $MODEL.\n"
        exit 1
fi

# Check to make sure pre-requisite files exists
if [[ ! -e config.txt.usb && ! -e config.txt.csi ]]; then
        printf "Missing config.txt.[usb|csi] files.  Please create files and re-run script.\n"
        exit 1
fi

backup-edid() {
        EDIDFILE="/etc/kvmd/tc358743-edid.hex"
        if [ -e $EDIDFILE ]; then
                cp $EDIDFILE $EDIDFILE.custom
        fi
} # end backup-edid

are-you-sure() {
   read -p "Are you sure? [y/n] " SURE
   case $SURE in
     Y|y)
       invalidinput=0
       ;;
     N|n)
       invalidinput=0
       exit 0
       ;;
     *)
       invalidinput=1
       echo "Try again!"
       ;;
   esac
} # end are-you-sure fn

if [[ "$1" == "-f" ]]; then
   printf "*** Performing actual commands ***\n"
   are-you-sure
else
   printf "*** ONLY showing you commands that will be run. ***\n"
fi

rw
backup-edid

TMPFILE="/tmp/kvmd-platform"; /bin/rm -f $TMPFILE
pacman -Q | grep kvmd-platform > $TMPFILE

OLDPLATFORM=`cat $TMPFILE | cut -d' ' -f1`
PLATFORM=`cat $TMPFILE | cut -d'-' -f1,2,3 | sed 's/v3/v2/g'`
CURRHW=`cat $TMPFILE | cut -d'-' -f4`

if [[ "$CURRHW" == "hdmi" ]]; then
        HW="usb"
        NEWHW=$( echo $CURRHW | sed -e 's/hdmi/hdmiusb/g' )
        printf "\n-> Switching from CSI to USB capture detected.\n"
        printf "\n*** NOTE:  Make take up to 2 mins before web portal responds after rebooting Pi. ***\n"
else    # going from USB to CSI
        HW="csi"
        NEWHW=$( echo $CURRHW | sed -e 's/hdmiusb/hdmi/g' )

        printf "\n-> Switching from USB to CSI capture detected.\n"
        invalidinput=1
        while [ $invalidinput -eq 1 ]; do
                printf "\n 1. V2 CSI\n 2. V3 HAT\n"
                read -p "Select [1/2] " V2V3
                case $V2V3 in
                1) invalidinput=0
                   ;;
                2) invalidinput=0
                   PLATFORM=`cat $TMPFILE | cut -d'-' -f1,2,3 | sed 's/v2/v3/g'`
                   ;;
                *) invalidinput=1
                   echo "Try again!"
                   ;;
                esac
        done

        # bugfix:  If initial platform was USB dongle, allow use of the CSI 2 chip at next boot
        systemctl enable kvmd-tc358743.service
fi
NEWPLATFORM="$PLATFORM-$NEWHW-rpi4"

invalidinput=1
while [ $invalidinput -eq 1 ]; do
        printf "\n$OLDPLATFORM -> $NEWPLATFORM\n"
        are-you-sure
done
echo

echo "Remove old platform and install new platform..."
echo "+ pacman -R $OLDPLATFORM"
if [[ "$1" == "-f" ]]; then yes | pacman -R $OLDPLATFORM 2> /dev/null; fi
echo "+ pacman -S $NEWPLATFORM"
if [[ "$1" == "-f" ]]; then yes | pacman -S $NEWPLATFORM 2> /dev/null; fi

echo
echo "Copy correct /boot/config.txt file..."
echo "+ cp config.txt.$HW $BOOTCONFIG"
if [[ "$1" == "-f" ]]; then cp config.txt.$HW $BOOTCONFIG; fi

if [[ "$1" == "-f" ]]; then
        printf "\n*** Please reboot to make changes take effect ***\n"
else
        printf "\n*** Re-run with -f to actually perform commands. ***\n"
fi
ro
