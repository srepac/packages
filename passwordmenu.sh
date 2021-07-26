#!/bin/bash
DIALOG="$( which dialog ) --clear"

# Check for expect package and expect script to perform htpasswd change
check-install-expect() {
  if [ $( pacman -Q | grep expect | wc -l ) -eq 0 ]; then
    progwin "INSTALLING MISSING PACKAGES" "rw; pacman -Syy; pacman --noconfirm --ask=4 -S expect; ro" 40
  fi

  EXPECTFILE="update-htpasswd.exp"
  if [ ! -e $EXPECTFILE ]; then
    mesgwin  "File not found."  "\nMissing $EXPECTFILE.  Please contact srepac@kvmnerds.com where to get the file."
    exit 1
  fi
} # end check-install-expect

# show inputbox -- reusable code
inputwin() {
  inputfile="/tmp/input$$"
  trap "rm -f $inputfile" 0 1 2 5 15

  $DIALOG --title "$1" --inputbox "$2" 10 51 2>$inputfile
} # end inputwin

# show password box -- reusable code
passwin() {
  passfile="/tmp/password$$"
  trap "rm -f $passfile" 0 1 2 5 15

  $DIALOG --title "$1" --passwordbox "$2" 10 40 2> $passfile
} # end passwin

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


change-webadmin() {
  username="$1"
  FILE="/etc/kvmd/htpasswd"

  if [[ "$2" == "new" ]]; then
    inputwin "NEW WEBUSER" "\nPlease enter new webusername to add"
    if [ $? -eq 0 ]; then
      if [ $( cat $inputfile | wc -w ) -gt 0 ]; then   # text was entered
        username=$( cat $inputfile )
      else
        username=""
      fi
    fi
  fi

  if [ $( echo $username | wc -w ) -gt 0 ]; then    # only proceed if some text was entered for new webuser name
    passwin "$TITLE"  "\nEnter new password for web user\n[ $username ]"
    if [ $? -eq 0 ]; then
      if [ `cat $passfile | wc -w` -gt 0 ]; then   # make sure user entered text; otherwise, go back to menu
        pass1=`cat $passfile`

        passwin "Confirm web password"  "\nRe-enter new password for web user\n[ $username ]"
        if [ $? -eq 0 ]; then

          if [ `cat $passfile | wc -w` -gt 0 ]; then   # make sure user entered text; otherwise, go back to menu
            pass2=`cat $passfile`

            if [[ "$pass1" == "$pass2" ]]; then
              rw
              progwin "kvmd-htpasswd set ${username}" "$EXPECTFILE $username $pass2" 30 80
              ro
              actionreqwin  "ACTION REQUIRED"  "\nIn order for the change to take effect, you need to restart services.\nThis will close your current web browser session.\nPlease re-login to web session after the restart of services.\n\nAre you sure you want to restart kvmd and nginx?" 15
              if [ $? -eq 0 ]; then
                CMD="systemctl restart kvmd kvmd-nginx"
                progwin "Restarting KVMD and NGINX services"  "$CMD && $( echo $CMD | sed s/restart/status/g )" 35 80
              fi
              progwin  "Webuser ${username} password updated"  "echo Contents of $FILE; cat $FILE"
            else
              mesgwin  "INFO MESSAGE"  "Passwords entered are not the same.  Password unchanged."
            fi
          fi
        fi
      fi
    fi
  fi
} # end change-webadmin


change-pass() {
  username="$1"
  FILE="/etc/shadow"

  progwin  "Original ${username} $FILE entry"  "grep -w $username $FILE"

  actionreqwin  "ACTION REQUIRED"  "\nAre your sure you want to change password for ${username}?"
  if [ $? -eq 0 ]; then
    passwin "Enter new ${username} password"  "\nEnter new ${username} password"

    if [ $? -eq 0 ]; then
      # If no text entered, go back to menu
      if [ `cat $passfile | wc -w` -gt 0 ]; then   # make sure user entered text; otherwise, go back to menu
        pass1=`cat $passfile`

        passwin "Confirm ${username} password"  "\nRe-enter new ${username} password"
        if [ $? -eq 0 ]; then

          if [ `cat $passfile | wc -w` -gt 0 ]; then   # make sure user entered text; otherwise, go back to menu
            pass2=`cat $passfile`

            if [[ "$pass1" == "$pass2" ]]; then
              rw
              echo ${username}:${pass1} > /tmp/pass$$; cat /tmp/pass$$ | chpasswd
              ro
              mesgwin  "INFO MESSAGE"  "Password successfully changed for [ ${username} ]."
              progwin  "Changed ${username} $FILE entry"  "grep -w $username $FILE"
            else
              mesgwin  "INFO MESSAGE"  "Passwords entered are not the same.  Password unchanged."
            fi
          fi

        fi

      fi
    fi

  fi
}


create-list() {     # generate list of webusers with dialog command
  ACTION="$1"
  LIST="/tmp/listusers"
  for i in $( kvmd-htpasswd list ); do
    echo "\"$i\"  \"$i\" \\"
  done > $LIST

  if [ "$2" == "new" ]; then
    echo "\"addnew\"  \"Add new user\"" >> $LIST
  fi

  GETUSER="/tmp/adminusers.cmd"; rm -f $GETUSER
  printf "$DIALOG --title \"WEB ADMIN USERS\" --menu \"Please pick which user to $ACTION:\\\\n\" 15 40 4 $(cat $LIST)" > $GETUSER

  chmod +x ${GETUSER}
} # end create-list


change-something() {
  case $selection in

    setpass)
      create-list "modify/set password" new

      tempfile=/tmp/webuser
      trap "rm -f $tempfile" 0 1 2 5 15
      $GETUSER 2> $tempfile
      if [ $? -eq 0 ]; then
        username=$( cat $tempfile )
        if [ $( grep -w $username /etc/kvmd/htpasswd | wc -l) -gt 0 ]; then
          TITLE="Change existing user password"
          change-webadmin ${username}
        else
          TITLE="Create new webuser - ${username}"
          change-webadmin ${username} new
        fi
      fi
      ;;

    deluser)
      create-list "delete"
      tempfile=/tmp/webuser
      trap "rm -f $tempfile" 0 1 2 5 15
      $GETUSER 2> $tempfile

      if [ $? -eq 0 ]; then
        username=$( cat $tempfile )
        if [ $( cat $tempfile | wc -w ) -gt 0 ]; then
          actionreqwin "DELETE WEBUSER"  "\nAre you sure you want to delete ${username}?\n"
          if [ $? -eq 0 ]; then
            progwin  "DELETED WEBUSER - ${username}"  "rw; kvmd-htpasswd del ${username}; ro" 25
            textwin  "/etc/kvmd/htpasswd"  "/etc/kvmd/htpasswd"
          fi
        fi
      fi
      ;;

    rootpass)
      change-pass root
      ;;

    quit)
      exit 0
      ;;

    *)
      mesgwin  "INFO MESSAGE"  "\nYour selection [ $selection ] is not yet implemented."
      ;;
  esac
  pass-menu
} # end change-passwords


pass-menu() {
  tempfile=/tmp/test$$
  trap "rm -f $tempfile" 0 1 2 5 15

  $DIALOG --title "PASSWORDS MENU" \
        --menu "Changing passwords menu - Hostname:  $(hostname)" 15 70 4 \
        "setpass"     "Set/change password for web user" \
        "deluser"     "Delete web user" \
        "rootpass"    "Change root password" \
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
} # end change-pass-menu


### MAIN STARTS HERE ###
check-install-expect
pass-menu


