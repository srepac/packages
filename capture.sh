#!/bin/bash
# This script performs a screen grab of Pi-KVM console running on this host
#
# Filename:  capture.sh
#
if [[ "$1" == "" || "$1" == "-h" || "$1" == "--help" ]]; then
	echo "usage: $0 <filename>	creates /tmp/filename.jpg image capture"
	exit 1
fi
# this is the default location, but you can change it to reflect NFS mount
CAPTUREDIR="/tmp"

FILENAME="${CAPTUREDIR}/$1.jpg"
echo "Performing screen capture of KVM console via command:"
echo "  curl --unix-socket /run/kvmd/ustreamer.sock http://localhost/snapshot -o $FILENAME" 
curl --unix-socket /run/kvmd/ustreamer.sock http://localhost/snapshot -o $FILENAME 