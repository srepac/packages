#!/bin/bash
# Created by @srepac for Pi-KVM Project to address https://github.com/pikvm/pikvm/issues/229
# ... as requested by @Arch1mede
#
# This script is designed to keep capturing image of console and compare from previous
# ... screen capture.  If no change, then delete previous capture (keeps most current).
# ... If there's a change, keep previous and new capture and record 30 seconds of video
#
# Filename:         monitor-console.sh
#
# Pre-requisites:   capture.sh          performs screen grab of pi-kvm console
#                   vid-capture.sh      checks/installs dependencies and performs video capture
#                                       ... of KVM console (script relies on a working ustreamer-dump
#                   active webui session
#
# Installing/Re-installing:
#
#       ./vid-capture.sh            # to install dependencies that this script relies on
#       rw; rm -f /var/spool/cron/root; ./monitor-console.sh; ro
#
#
# Troubleshooting/Uninstalling:
#
# To "uninstall" the script from root crontab, run:
#
#       rw; rm /var/spool/cron/root; ro
#
# Logfile is located in CAPTUREDIR/monitorconsole-<hostname>.log file to help in troubleshooting script output
#
# HISTORY:
#
#       srepac  03/24   created script and sent to @Arch1mede to test
#       srepac  03/25   updated to include variables for # seconds to record and size difference threshold
#       srepac  03/27   completed documentation of script
#       srepac  03/28   check ustreamer-dump is not running before performing video capture
#       srepac  03/30   check to make sure webui session is open, required for screen capture
#       srepac  04/04   check to make sure CAPTUREDIR= exists before doing anything else
#
#set -x
# number of seconds of video to capture from console (to assist in troubleshooting purposes)
TIME=30
# size difference >= this KB threshold before capturing video
SIZEDIFF=5

CAPTURESH="/root/capture.sh"
if [[ ! -e $CAPTURESH ]]; then
        echo "-> Missing required script [ capture.sh ]; please contact @srepac for the script."
        exit 1
fi

# Uses same capture directory as the capture.sh script
CAPTUREDIR=$( grep ^CAPTUREDIR= $CAPTURESH | grep -v '^#' | awk -F\= '{print $2}' | sed -e 's/ //g' -e 's/\"//g' )
if [[ "$CAPTUREDIR" == "" ]]; then CAPTUREDIR="/tmp"; fi

# check to make sure CAPTUREDIR exists before doing anything else
if [[ ! -e $CAPTUREDIR ]]; then
        echo "-> $CAPTUREDIR does not exist.  Please make sure filesystem is mounted."
        exit 1
fi

LOGFILE="$CAPTUREDIR/monitorconsole-$(hostname).log"; touch $LOGFILE
echo "------------------" >> $LOGFILE; date >> $LOGFILE

# Install and enable cronie service
if [[ $( which crontab | wc -l ) -le 0 ]]; then
        echo "-> Installing cronie package and dependencies and Enabling cronie services." | tee -a $LOGFILE
        pacman -S cronie
        systemctl enable cronie
fi

# Start cronie service, in case not running
if [[ $( systemctl status cronie | grep Active: | grep inactive | wc -l ) -eq 1 ]]; then
        echo "-> Starting cronie services to allow cronjobs." | tee -a $LOGFILE
        systemctl start cronie
fi

# setup cronjob for root and load it based on pi model
if [[ ! -e /var/spool/cron/root ]]; then
        # Make sure there's at least one webui connection to Pi-KVM for screen capture to work
        read -p "Login to web console at https://$(hostname)/ first, then press ENTER to continue... " CONTINUE

        echo "-> Creating base screen grab of console"; $CAPTURESH $(hostname) > /dev/null 2> /dev/null

        echo -n "-> Installing root crontab entry as follows for Model - "

        # based on pi4 or zero, cronjob should be 1 minute for pi 4 and 2 minutes for pi zero
        MODEL=$(tr -d '\0' </proc/device-tree/model | awk '{print $3}')
        case $MODEL in
            4|3)        # every minute
                echo "Pi 4"
                echo "*/1 * * * * /root/monitor-console.sh" > /tmp/rootcron
                ;;
            Zero)       # every 2 minutes
                echo "Pi Zero"
                echo "*/2 * * * * /root/monitor-console.sh" > /tmp/rootcron
                ;;
            *)          # every 5 minutes
                echo "Pi Other"
                echo "*/5 * * * * /root/monitor-console.sh" > /tmp/rootcron
                ;;
        esac

        cat /tmp/rootcron; echo
        crontab /tmp/rootcron
fi

# New screen grab filename (without .jpg extension); when capture.sh is called it will add .jpg extension
NEWFILE="$(hostname)-$(date +%s)"
# Make sure there are at least 1 capture file from before.  If not, make the previous and newfile the same file
if [[ $( ls $CAPTUREDIR/$(hostname)*.jpg 2> /dev/null | wc -l ) -le 0 ]]; then
        PREVFILE=${CAPTUREDIR}/${NEWFILE}.jpg
else
        PREVFILE=$( ls -ltr ${CAPTUREDIR}/$(hostname)*.jpg | tail -1 | awk '{print $NF}' )
fi

# UNCOMMENT below for troubleshooting purposes
#printf "\nPREVFILE=$PREVFILE\nNEWFILE=$CAPTUREDIR/$NEWFILE.jpg\n\n" | tee -a $LOGFILE

# call to screen grab script (capture.sh)
$CAPTURESH $NEWFILE 2> /dev/null > /dev/null
if [[ $? -ne 0 ]]; then
        echo "-> Screen grab not successful.  Please connect to active webui session at https://$(hostname)/" | tee -a $LOGFILE
        exit 1
fi

# Take new file size and prev file size and divide by 1024 (to convert to >KB)
ls -l ${CAPTUREDIR}/${NEWFILE}.jpg $PREVFILE | tee -a $LOGFILE
NEWSIZE=$( echo "`ls -l ${CAPTUREDIR}/${NEWFILE}.jpg | awk '{print $5}'` / 1024" | bc )
PREVSIZE=$( echo "`ls -l $PREVFILE | awk '{print $5}'` / 1024" | bc )

# Difference in size is >= threshold size in KB, then keep both, else delete previous file
DIFFSIZE=$( echo "( $NEWSIZE - $PREVSIZE )" | bc )
if [[ $DIFFSIZE -lt 0 ]]; then DIFFSIZE=$(echo "$DIFFSIZE * -1" | bc); fi
if [[ $DIFFSIZE -ge $SIZEDIFF ]]; then
        echo "New file size = ${NEWSIZE}KB is different than previous file size = ${PREVSIZE}KB" | tee -a $LOGFILE

        # Check to see if another ustreamer-dump is running before running capture
        if [[ $( ps -ef | grep ustreamer-dump | grep -v grep | wc -l) -ge 1 ]]; then
                echo "Another ustreamer-dump is currently running.  Skipping video capture until previous one completes." | tee -a $LOGFILE
        else
                echo "Capturing $TIME second console video into ${CAPTUREDIR}/${NEWFILE}.mp4" | tee -a $LOGFILE
                ustreamer-dump --sink kvmd::ustreamer::h264 --output - | ffmpeg -use_wallclock_as_timestamps 1 -i pipe: -c:v copy -t $TIME ${CAPTUREDIR}/${NEWFILE}.mp4 2> /dev/null | tee -a $LOGFILE
        fi
else
        echo "New file size = ${NEWSIZE}KB is about the same as previous file size = ${PREVSIZE}KB.  Removing previous file." | tee -a $LOGFILE
        rm -f $PREVFILE
fi