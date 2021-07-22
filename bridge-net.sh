#!/bin/bash
# This script is to address network bridging the Pi-KVM with a client PC
# ... as requested by @Markrosoft
#
# *** ONLY USE THIS CONFIG IF eth0 IS CONFIGURED FOR DHCP ON Pi-KVM ***
# YOU HAVE TO MAKE SURE USB ETHERNET ADAPTER IS PLUGGED INTO THE SAME PORT!!!
#
####
# USE CASE:  No need to worry about wifi settings on Pi-KVM
# User has only one network cable that connects to their PC and they need help with their computer.
#
# To help troubleshoot and fix the issue remotely, admin sends pi4-kvm and usb ethernet + hdmi loop capture to user...
# User connects existing net cable to pi4 gigE NIC, and plugs net cable from usb ethernet to their PC...
# User connects their hdmi output cable to loop capture in, hdmi out to their monitor and usb cable from loop capture
# ... to usb2 (bottom left) port on pi4... power on both systems... and they both have network connection...
# Admin can then remote in to user computer via pi-kvm webui and user can see what they're doing
# RESULT:  shared network connection to both devices... only requires one switch port
####
#
# How-To bridge networks (for ethernet pass-through) overview steps (script does steps 2-6 below)
# ... Admin just has to plug in ethernet adapter into Pi then runs this script to do the rest.
#
# 1.  Add a usb ethernet adapter to your pi
# 2.  ifconfig to find your usb device name
# 3.  Create /etc/netctl/kvm-bridge file
#     Add the following (replace ethusb with usb ethernet device name):

create-file() {  # create new file function
printf "
###
Description=\"Bridge Interface br10 : eth0 ${USBETH}\"
Interface=br10
Connection=bridge
BindsToInterfaces=(eth0 ${USBETH})
IP=dhcp
# If you want also for DHCPv6,uncomment below line
#IP6=dhcp
## Ignore (R)STP and immediately activate the bridge
SkipForwardingDelay=yes
###
" > ${BRIDGEFILE}
} # end create-file function

# 4.  netctl start kvm-bridge
# 5.  netctl enable kvm-bridge
# 6.  If changes are made, run: netctl reenable kvm-bridge

# --- MAIN STARTS HERE ---
rw
BRIDGE="kvm-bridge"
BRIDGEFILE="/etc/netctl/$BRIDGE"
USBETH=$( ifconfig -a | grep ^enp | awk -F: '{print $1}' )

# -f option forces re-install of kvm-bridge
if [[ "$1" == "-f" ]]; then
        netctl stop $BRIDGE
        netctl disable $BRIDGE
        rm -f $BRIDGEFILE
fi

if [[ ! -e $BRIDGEFILE ]]; then
        echo "Creating new [ $BRIDGEFILE ] file with the following: "
        create-file
        change=1
else
        /bin/rm -f $BRIDGEFILE.new
        cat $BRIDGEFILE | sed -e "s/enp1s0u2u[0-9]/$USBETH/g" > $BRIDGEFILE.new
        if [[ $( diff $BRIDGEFILE.new $BRIDGEFILE | wc -l ) -gt 0 ]]; then
                echo "New changes found in config file.  Will use the following in [ $BRIDGEFILE ]"
                cp $BRIDGEFILE.new $BRIDGEFILE
                change=1
        else
                echo "No new changes found.  Will use the following in [ $BRIDGEFILE ]"
                change=0
        fi
fi

# show contents of file to use
cat $BRIDGEFILE

if [[ $( netctl status $BRIDGE | grep Active: | grep inactive | wc -l ) -eq 1 ]]; then
        echo netctl start $BRIDGE
        netctl start $BRIDGE
else
        echo "netctl is already running"
fi

echo netctl enable $BRIDGE
netctl enable $BRIDGE

if [[ $change -eq 1 ]]; then
        echo netctl reenable $BRIDGE
        netctl reenable $BRIDGE
fi
ro
