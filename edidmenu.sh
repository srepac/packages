#!/bin/bash
# EDID Selector script as requested and hounded by @Arch1mede
# 
# This script will look for /etc/kvmd/*.edid files and use that as a list
# ... for the user to pick an EDID from and try to see if it solves the
# ... user's issue (i.e. not able to get to BIOS or garbled garbage)
# User can add their own EDID file to /etc/kvmd/<filename>.edid
#
# The script will then apply the EDID temporarily by copying the EDID file
# ... into /root/edid.hex and then running the following: 
#     v4l2-ctl --device=/dev/kvmd-video --set-edid=file=/root/edid.hex --fix-edid-checksums
# If the chosen edid resolves user's issue, then they can copy the chosen EDID
# ... into /etc/kvmd/tc358743-edid.hex file which will be loaded at boot.
#
DIALOG="$( which dialog ) --clear"
SCRIPTDIR="/usr/local/bin"

# get-edid-files function
get-edid-files() {
  EDIDLINKS="/tmp/EDID"; rm -f $EDIDLINKS
  EDIDWEB="${WEBSITE}/EDID"
  rw 
  wget -O ${EDIDLINKS} ${EDIDWEB} > /dev/null 2>&1
  for i in $( grep 'a href' ${EDIDLINKS} | grep -v '\.\.' | cut -d'>' -f3 | cut -d'"' -f2 ); do
    wget -O ${KVMDIR}/${i} ${EDIDWEB}/$i > /dev/null 2>&1
  done 
  ro
} # end get-edid-files

# show inputbox -- reusable code
inputwin() {
  inputfile="/tmp/input$$"
  trap "rm -f $inputfile" 0 1 2 5 15

  $DIALOG --title "$1" --inputbox "$2" 10 51 2>$inputfile
} # end inputwin

# show a programbox window -- reusable code
progwin() {       # default: 10 lines high and 70 chars wide
  HT=10
  WIDTH=70
  if [[ "$3" != "" ]]; then HT=$3; fi
  if [[ "$4" != "" ]]; then WIDTH=$4; fi
  $DIALOG --title "$1" --prgbox "$2" $HT $WIDTH
} # end progwin

# show confirmation window (yes or no options only) -- reusable code
actionreqwin() {  # default: 10 lines high and 70 chars wide
  HT=10
  WIDTH=70
  if [[ "$3" != "" ]]; then HT=$3; fi
  if [[ "$4" != "" ]]; then WIDTH=$4; fi
  $DIALOG --title "$1" --yesno "$2" $HT $WIDTH
} # end actionreqwin

# show a message window (only option is to close window) -- reusable code
mesgwin() {       # default: 10 lines high and 70 chars wide
  HT=10
  WIDTH=70
  if [[ "$3" != "" ]]; then HT=$3; fi
  if [[ "$4" != "" ]]; then WIDTH=$4; fi
  $DIALOG --title "$1" --msgbox "$2" $HT $WIDTH
} # end mesgwin

# show contents of a file into textbox (only option is to close window) -- reusable code
textwin() {       # default: 10 lines high and 70 chars wide
  HT=10
  WIDTH=70
  if [[ "$3" != "" ]]; then HT=$3; fi
  if [[ "$4" != "" ]]; then WIDTH=$4; fi
  $DIALOG --title "$1" --textbox "$2" $HT $WIDTH
} # end textwin


create-list() {     # generate list of edids to use 
  # Generate the dialog command to dynamically choose edids based on contents of /etc/kvmd/edid.files
  # ... the initial edid files should be called default.edid, gah77-1280x1024.edid, and gah77-1280x1080.edid
  # ... If you want to add additional edids to try, create the file with the .edid extension in /etc/kvmd/
  #
  EDIDFILES=$( ls /etc/kvmd/*.edid )
  LIST="/tmp/edidlist"
  for i in $( echo $EDIDFILES ); do
    echo "\"$i\"  \"$i\" \\"
  done > $LIST

  GETEDID="/tmp/adminusers.cmd"; rm -f $GETEDID
  printf "$DIALOG --title \"EDID CHOOSER MENU\" --menu \"Please pick edid you want to try:\\\\n\" 15 70 4 $(cat $LIST)" > ${GETEDID}
  chmod +x ${GETEDID}
} # end create-list


change-something() {
  case $selection in

    currentedid)
      FILECONTENTS=$( cat $MASTEREDID )
      mesgwin "$MASTEREDID" "$FILECONTENTS" 15 80
      ;;

    setedid)
      create-list

      tempfile=/tmp/webuser
      trap "rm -f $tempfile" 0 1 2 5 15
      $GETEDID 2> $tempfile

      if [ $? -eq 0 ]; then
        CHOSENEDID=$( cat $tempfile )

        # user selected an edid, so copy the relevant file into /root/edid.hex
        # test it by running  v4l2-ctl --device=/dev/kvmd-video --set-edid=file=/root/edid.hex --fix-edid-checksums
        rw; cp $CHOSENEDID $ROOTEDID
        progwin  "Applying $CHOSENEDID now"  "v4l2-ctl --device=/dev/kvmd-video --set-edid=file=/root/edid.hex --fix-edid-checksums"
        ro 

        mesgwin  "Test $CHOSENEDID without rebooting Pi-KVM"  "\nIn order to test the chosen EDID, please reboot target PC now and check web session to see if that fixed the issue.  If it did, then you can apply it permanently by answering YES to the next question.\n\nOtherwise, please say NO and retry another EDID." 15

        if [ $? -eq 0 ]; then

          actionreqwin "APPLY EDID PERMANENTLY" "\nChosen edid ${CHOSENEDID} will overwrite ${MASTEREDID} file.\n\nAre you sure you want to apply the chosen EDID?"

          if [ $? -eq 0 ]; then 
            rw
            # make backup and overwrite master edid file
            cp $MASTEREDID $MASTEREDID.bkup
            chmod 644 $MASTEREDID
            cp $CHOSENEDID $MASTEREDID
            ro
          fi

        fi
         
      fi
      ;;

    quit)
      exit 0
      ;;

    *)
      mesgwin  "INFO MESSAGE"  "\nYour selection [ $selection ] is not yet implemented."
      ;;
  esac
  edid-menu
} # end change-passwords


edid-menu() {
  tempfile=/tmp/test$$
  trap "rm -f $tempfile" 0 1 2 5 15

  $DIALOG --title "MAIN EDID MENU" \
        --menu "Set/change EDID menu - Hostname:  $(hostname)" 15 70 4 \
        "currentedid" "Show current EDID" \
        "setedid"     "Set/change EDID" \
        "quit"        "Quit program" 2> $tempfile

  retval=$?
  selection=`cat $tempfile`

  case $retval in
    0)
      change-something
      ;;
    1)  # Cancel pressed.
      exit 0
      ;;
    2)  # ESC pressed.
      exit 0
      ;;
  esac
} # end edid-menu


### MAIN STARTS HERE ###
MASTEREDID="/etc/kvmd/tc358743-edid.hex"
ROOTEDID="/root/edid.hex" 
WEBSITE="https://kvmnerds.com:8443/PiKVM"
KVMDIR="/etc/kvmd"

if [ `pacman -Q | grep kvmd-platform | grep hdmiusb | wc -l` -eq 1 ]; then
  mesgwin "INFO MESSAGE" "\nYou are using USB HDMI dongle.\nChanging EDIDs only works with CSI bridge."
  exit 1
else
  if [ ! -e $KVMDIR/default.edid ]; then
    get-edid-files
  fi
  edid-menu
fi

