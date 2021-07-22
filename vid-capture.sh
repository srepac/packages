#!/bin/bash
# Pre-requisites:  https://github.com/pikvm/pikvm/blob/master/pages/video.md
# 1.  ffmpeg package is installed
# 2.  gpu_mem=256 in /boot/config.txt for usb-hdmi or gpu_mem=64 for csi bridge or gpu_mem=128 for v3
# 3.  /etc/kvmd/override.yaml memory sink options
### ACTIVE webui session is required for this capture to work
#
# gpu_mem=16 is default for USB-HDMI
# If pre-reqs are not met, this script will fix #1 and #2, but #2 applies to USB-HDMI and will require reboot
# Lastly, #3 can be done manually as per the article above after reboot.
#
# /tmp default size is 844MB on Pi4, and about 117MB on Pi Zero
# this is the default, but can be changed to reflect NFS mount location
CAPTUREDIR="/tmp"

if [[ "$1" == "" ]]; then
        echo "$0 <filename>     creates ${CAPTUREDIR}/filename.mp4 video capture file"
        exit 1
fi

rw
if [[ $(which ffmpeg | wc -l) -le 0 ]]; then
        echo "Missing package dependency [ ffmpeg ].  Installing ffmpeg and required dependencies"
        pacman -S ffmpeg
fi
if [[ $(egrep 'gpu_mem=64|gpu_mem=256|gpu_mem=128' /boot/config.txt | wc -l) -le 0 ]]; then
        echo "/boot/config.txt needs to be updated to reflect gpu_mem=256, and reboot required"
        cp /boot/config.txt /boot/config.txt.orig
        sed -e "s/gpu_mem=[0-9]*/gpu_mem=256/g" /boot/config.txt > /tmp/config.txt
        cp /tmp/config.txt /boot/config.txt
        echo "Updated gpu_mem=256 in /boot/config.txt.  Please reboot and then retry this script again."
        exit 1
fi

# v3 image sink built-in; check for /etc/kvmd/override.yaml for all other versions
if [[ $( pacman -Q | grep kvmd-platform | grep v3 | wc -l ) -lt 1 ]]; then
    if [[ $( grep sink /etc/kvmd/override.yaml | wc -l) -le 0 ]]; then
        echo "Missing sink=kvmd::ustreamer::h264 entry in /etc/kvmd/override.yaml"
        echo "To fix this, please see https://github.com/pikvm/pikvm/blob/master/pages/video.md"
        exit 1
    fi
fi

FILENAME="${CAPTUREDIR}/$1.mp4"; rm -f $FILENAME
echo "Press CTRL+C to stop capturing video to $FILENAME."

ustreamer-dump --sink kvmd::ustreamer::h264 --output - | ffmpeg -use_wallclock_as_timestamps 1 -i pipe: -c:v copy $FILENAME 2> /dev/null

if [[ ! -e $FILENAME ]]; then
	echo "Video capture did not work.  Please open a webui session to https://$(hostname)/ then try again."
else
	echo
	ls -l $FILENAME
	echo "Captured video is in $FILENAME"
fi
ro
