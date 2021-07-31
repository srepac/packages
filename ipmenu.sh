#!/bin/bash
# This script performs network configuration for PiKVM
#
# HISTORY:
#   07/29/2021  srepac	v1.0 wrote initial script
#   07/30/2021	srepac	@invadermonks tested script (stdout grep errors found but did not affect
#                       ... expected behavior to change from DHCP to STATIC and vice versa
#                       v1.1 fixed bug as per above
#                       @Arch1mede tested bug fixes and confirmed ready for public use
# VER=1.1
#
ETH0="/etc/systemd/network/eth0.network"
# Find out which SSID file is in use for wlan0
SSID=$( netctl-auto list | grep '^*' | awk '{print $2}' )
WIFI="/etc/netctl/${SSID}"

DIALOG="$( which dialog ) --clear"

chk-packages() {  # make sure bind is installed
  if [ $( pacman -Q | grep bind | wc -l) -eq 0 ]; then
    progwin "Installing missing dependencies" "rw; pacman -Syy; yes | pacman -S bind ; ro" 40
  fi
} #

# show inputbox -- reusable code
inputwin() {
  inputfile="/tmp/input$$"
  trap "rm -f $inputfile" 0 1 2 5 15

  $DIALOG --backtitle "$1" --title "$1" --inputbox "$2" 18 60 2>$inputfile
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
textwin() {       # default: 25 lines high and 80 chars wide
  HT=25
  WIDTH=80
  if [[ "$3" != "" ]]; then HT=$3; fi
  if [[ "$4" != "" ]]; then WIDTH=$4; fi
  $DIALOG --title "$1" --textbox "$2" $HT $WIDTH
} # end textwin


chk-ip-inuse() {  # check to make sure that static IP user typed in is not currently in use
  CHKIP="$1"

  # ping the IP and if it doesn't respond, it means IP is available, else flag IP as invalid (so ask user again)
  # ... also, verify that the IP address isn't in eth0/wlan0 configuration
  PINGOUT="/tmp/ping.out"; /bin/rm -f $PINGOUT
  progwin "Pinging IP $CHKIP" "echo Please wait... && ping -c4 $CHKIP | tee -a ${PINGOUT}" 15
  if [ `cat $PINGOUT | grep '100% packet loss' | wc -l` -eq 1 ]; then    # IP is available

    # if no SSID, then don't check WIFI, else check both (added after @invadermonks tested script)
    # ... he did not have wifi connected to SSID so he was getting grep errors in stdout 
    if [[ "$SSID" == "" ]]; then
      ADAPTERS="$ETH0" 
    else
      ADAPTERS="$ETH0 $WIFI" 
    fi

    if [ `grep $CHKIP $ADAPTERS| wc -l` -eq 0 ]; then   # check IP entered is not in wlan0 and eth0 config 
      if [ `host $CHKIP | awk '{print $NF}' | grep NXDOMAIN | wc -l` -gt 0 ]; then  # IP has no reverse DNS entry
        MESSAGE="\n$CHKIP is AVAILABLE.\n\n - no reverse DNS entry found.\n - IP is not in use by other interfaces on this PiKVM.\n\nProceeding with $INTERFACE static configuration." 
        mesgwin "INFO MESSAGE" "$MESSAGE" 12
        invalid=0
      else
        mesgwin "INFO MESSAGE" "\n$CHKIP has a reverse DNS entry IN USE by another device.\nPlease try another IP."
        invalid=1
      fi

    else
      mesgwin "INFO MESSAGE" "\n$CHKIP exists in the eth0/wlan0 static configuration.\nPlease try another IP."
      invalid=1

    fi
  else
    mesgwin "INFO MESSAGE" "\n$CHKIP is IN USE by another device.\nPlease try another IP."
    invalid=1
  fi
} # end chk-ip-inuse function 


change-ip() {
  # take in IP.ad.dr.ess/CIDR notation and ask user to allocate what IP to use
  INTERFACE="$2"
  IPCIDR="$1"
  CIDR=$( echo $IPCIDR | cut -d'/' -f2 )
   
  OCTET1=$( echo $IPCIDR | cut -d'.' -f1 )
  OCTET2=$( echo $IPCIDR | cut -d'.' -f2 )
  OCTET3=$( echo $IPCIDR | cut -d'.' -f3 )
  OCTET4=$( echo $IPCIDR | cut -d'.' -f4 | cut -d'/' -f1 )

  NUMFULLCIDR=$( echo $CIDR / 8 | bc )
  LEFTOVER=$( echo $CIDR % 8 | bc )

  increment=$( echo "2^(8-$LEFTOVER)" | bc )  
  netbits=$( echo "256 - $increment" | bc )  
  let "startip=$NETID + 1"

  case $NUMFULLCIDR in 
    1) NETID=$( echo "( $OCTET2 / $increment ) * $increment" | bc )
       SUBNET="$OCTET1" 
       NETWORK="$SUBNET.$NETID" 
       MASK="255.$netbits.0.0"
       OCTET=2
       ;;
    2) NETID=$( echo "( $OCTET3 / $increment ) * $increment" | bc )
       SUBNET="$OCTET1.$OCTET2" 
       MASK="255.255.$netbits.0" 
       NETWORK="$SUBNET.$NETID" 
       OCTET=3
       ;;
    3) NETID=$( echo "( $OCTET4 / $increment ) * $increment" | bc )
       SUBNET="$OCTET1.$OCTET2.$OCTET3"
       MASK="255.255.255.$netbits" 
       NETWORK="$SUBNET.$NETID" 
       OCTET=4
       ;;
    *)
       let "startip=$NETID + 1"
       ;;
  esac

  HOSTS=$( echo "2^(32-$CIDR) - 2" | bc )
  MAXIP=$( echo "$HOSTS + $NETID" | bc )

  tmpipfile="/tmp/setup-$INTERFACE.out"; /bin/rm -f $tmpipfile
  MESSAGE="\nDHCP IP:    $IPCIDR\nNETMASK:    $MASK\nNETWORK:    $NETWORK\nIncrement:  $increment\n# host IPs: $HOSTS\n\nPlease enter complete static IP address below:\n(hint: change octet $OCTET)"
 
  $DIALOG --backtitle "Network Interface Setup" \
       --title "Network Configuration - $INTERFACE" \
       --form "$MESSAGE" 18 60 2 \
       "IP Address:" 1 1 "$NETWORK" 1 16 16 15 \
       2> $tmpipfile

  if [ $? -eq 0 ]; then
    IPADDR=$( cat $tmpipfile )
    if [[ $( echo $IPADDR | wc -w ) -gt 0 ]]; then   # make sure there's at least one entry
      chk-ip-inuse $IPADDR
    fi
  else
    main-menu
  fi
} # end change-ip function to enter IP address and runs function call to check if IP in use or not


eth-static2dhcp() {
  TMPETH0="/tmp/eth0.network"; /bin/rm -f $TMPETH0
  cat $ETH0 | sed -e 's/Address=*.*.*.*/DHCP=yes/' -e 's/Gateway=*.*.*.*/ /g' -e 's/DNS=*.*.*.*/ /g' | grep -v '^ $' >> $TMPETH0
  echo >> $TMPETH0

  printf "
# Use same IP by forcing to use MAC address for clientID
[DHCP]
ClientIdentifier=mac\n" >> $TMPETH0

  textwin "$TMPETH0" $TMPETH0 20
  actionreqwin "Change to eth0 DHCP config" "\nAre you sure you want to change eth0 to DHCP?"
  if [ $? -eq 0 ]; then
    actionreqwin "Confirm apply eth0 DHCP config" "\nAre you REALLY SURE you want to change eth0 to DHCP?"
    if [ $? -eq 0 ]; then
      rw; cp $ETH0 $ETH0.bak; cp $TMPETH0 $ETH0; ro
    fi
  fi
} # end eth-static2dhcp


eth-dhcp2static() {
  ETHSTATIC="/tmp/eth0.static"; /bin/rm -f $ETHSTATIC
  CURRIP=$( ip -br a | egrep eth0 | awk '{print $3}' ) 
  # TESTING ONLY
  #CURRIP="172.16.0.88/26"
 
  printf "[Match]\nName=eth0\n\n[Network]\n" >> $ETHSTATIC

  invalid=1
  while [ $invalid -eq 1 ]; do 
    change-ip $CURRIP eth0
  done
  echo "Address=${IPADDR}/$CIDR" >> $ETHSTATIC

  GW=$( netstat -nr | grep ^0.0.0.0 | awk '{print $2}' | uniq ) 
  echo "Gateway=$GW" >> $ETHSTATIC

  for i in `cat /etc/resolv.conf | grep nameserver | awk '{print $2}'`; do echo "DNS=$i"; done >> $ETHSTATIC
  
  textwin "$ETHSTATIC" $ETHSTATIC 20
  actionreqwin "Change to eth0 STATIC config" "\nAre you sure you want to change eth0 to STATIC?"
  if [ $? -eq 0 ]; then
    actionreqwin "Confirm apply eth0 STATIC config" "\nAre you REALLY SURE you want to change eth0 to STATIC?"
    if [ $? -eq 0 ]; then
      rw; cp $ETH0 $ETH0.bak; cp $ETHSTATIC $ETH0; ro
    fi
  fi
} # end eth-dhcp-to-static


wlan-dhcp2static() {
  WLANSTATIC="/tmp/wlan0.static"; /bin/rm -f $WLANSTATIC
  CURRIP=$( ip -br a | egrep wlan0 | awk '{print $3}' ) 

  sed '/^IP=dhcp/d' $WIFI >> $WLANSTATIC	# remove IP=dhcp line
  printf "\nIP=static\n" >> $WLANSTATIC		# create new IP=static line 

  invalid=1
  while [ $invalid -eq 1 ]; do 
    change-ip $CURRIP wlan0
  done
  echo "Address=('"${IPADDR}"/$CIDR')" >> $WLANSTATIC

  GW=$( netstat -nr | grep ^0.0.0.0 | awk '{print $2}' | uniq ) 
  echo "Gateway=('$GW')" >> $WLANSTATIC

  echo -n "DNS=(\"" >> $WLANSTATIC
  for i in `cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | grep -v ':'`; do 
    echo -n "$i "
  done | sed 's/ $//g' >> $WLANSTATIC
  echo "\")" >> $WLANSTATIC 

  textwin "$WLANSTATIC" $WLANSTATIC 30 80
  actionreqwin "Change to wlan0 STATIC config" "\nAre you sure you want to change wlan0 to STATIC?"
  if [ $? -eq 0 ]; then
    actionreqwin "Confirm apply wlan0 STATIC config" "\nAre you REALLY SURE you want to change wlan0 to STATIC?"
    if [ $? -eq 0 ]; then
      rw; cp $WIFI $WIFI.bak ; cp $WLANSTATIC $WIFI; ro
    fi
  fi
} # end wlan-dhcp2static


wlan-static2dhcp() {
  CURRIP=$( ip -br a | egrep wlan0 | awk '{print $3}' ) 
  TMPFILE="/tmp/wifi.dhcp"
  cat $WIFI | egrep -v 'Address|Gateway|DNS' | sed 's/^IP=[a-z]*/IP=dhcp/g' > $TMPFILE 

  textwin "$TMPFILE" $TMPFILE
  actionreqwin "Change to wlan0 DHCP config" "\nAre you sure you want to change wlan0 to DHCP?"
  if [ $? -eq 0 ]; then
    actionreqwin "Confirm apply wlan0 DHCP config" "\nAre you REALLY SURE you want to change wlan0 to DHCP?"
    if [ $? -eq 0 ]; then
      rw; cp $WIFI $WIFI.bak ; cp $TMPFILE $WIFI; ro
    fi
  fi
} # end wlan-dhcp2static


show-ip() {
  CMD="ip -br a | egrep 'eth0|wlan0' | awk '{print \$1, \$3}'"
  progwin "IP Addresses - $(hostname)" "$CMD" 10 40
} 


ip-pi4() {
  case $selection in

    ipaddress)
      show-ip
      ;;

    currentwlan)
      chk-no-wifi 
      textwin "Current $WIFI config" "$WIFI"
      ;;

    currenteth)
      textwin "Current $ETH0 config" "$ETH0"
      ;;

    staticeth)
      if [ $( grep Address= $ETH0 | wc -l ) -gt 0 ]; then
        textwin "eth0 already set to STATIC" "$ETH0"
      else
        eth-dhcp2static
      fi
      ;;

    ethdhcp)
      if [ $( grep ^DHCP=yes $ETH0 | wc -l ) -gt 0 ]; then
        textwin "eth0 already set to DHCP" "$ETH0"
      else
        eth-static2dhcp
      fi
      ;;

    staticwlan) 
      chk-no-wifi 
      if [ $( grep ^IP=static $WIFI | wc -l ) -gt 0 ]; then
        textwin "wlan0 already set to STATIC" "$WIFI"
      else
        wlan-dhcp2static
      fi
      ;;

    wlandhcp) 
      chk-no-wifi 
      if [ $( grep ^IP=dhcp $WIFI | wc -l ) -gt 0 ]; then
        textwin "wlan0 already set to DHCP" "$WIFI"
      else
        wlan-static2dhcp
      fi
      ;;

    reboot)
      reboot && exit && exit 
      ;;

    quit)
      exit 0
      ;;

    *)
      mesgwin  "INFO MESSAGE"  "\nYour selection [ $selection ] is not yet implemented."
      ;;
  esac
  main-menu
} # end ip-pi4 function


ip-zero() {
  case $selection in

    ipaddress)
      show-ip
      ;;

    currentwlan)
      chk-no-wifi 
      textwin "Current $WIFI config" "$WIFI"
      ;;

    staticwlan) 
      chk-no-wifi 
      if [ $( grep ^IP=static $WIFI | wc -l ) -gt 0 ]; then
        textwin "wlan0 already set to STATIC" "$WIFI"
      else
        wlan-dhcp2static
      fi
      ;;

    dhcpwlan) 
      chk-no-wifi 
      if [ $( grep ^IP=dhcp $WIFI | wc -l ) -gt 0 ]; then
        textwin "wlan0 already set to DHCP" "$WIFI"
      else
        wlan-static2dhcp
      fi
      ;;

    reboot)
      reboot && exit && exit 
      ;;

    quit)
      exit 0
      ;;

    *)
      mesgwin  "INFO MESSAGE"  "\nYour selection [ $selection ] is not yet implemented."
      ;;
  esac
  main-menu 
} # end ip-zero function
     

chk-no-wifi() {   # if not connected to SSID, tell user to connect first and then show main-menu 
  if [[ "$SSID" == "" ]]; then
    mesgwin "INFO MESSAGE"  "\nYou need to connect wifi to an SSID first, then try again\n"
    main-menu  
  fi
} # 


pi4-menu() {
  tempfile=/tmp/test$$
  trap "rm -f $tempfile" 0 1 2 5 15

  $DIALOG --title "PiKVM IP CONFIG MENU" \
        --menu "Change IP configuration for Hostname: $(hostname)\n\n*** Changes will not take effect until you reboot. ***\n" 18 70 4 \
	"ipaddress"	"Show IP address(es)" \
        "currenteth"    "Current eth0 config - $ETHCONF" \
        "currentwlan"   "Current wlan0 config - $WLANCONF" \
        "ethdhcp"       "Set eth0 to use DHCP" \
        "wlandhcp"      "Set wlan0 to use DHCP" \
        "staticeth"     "Set eth0 to use STATIC" \
        "staticwlan"    "Set wlan0 to use STATIC" \
	"reboot"	"Reboot PiKVM" \
        "quit"          "Quit program" 2> $tempfile

  retval=$?
  selection=`cat $tempfile`

  case $retval in
    0)
      ip-pi4 
      ;;
    1)  # Cancel pressed.
      exit 0
      ;;
    2)  # ESC pressed.
      exit 0
      ;;
  esac
} # end pi4-menu 


zero-menu() {
  tempfile=/tmp/test$$
  trap "rm -f $tempfile" 0 1 2 5 15

  $DIALOG --title "Pi Zero IP CONFIG MENU" \
	--menu "Change IP configuration for Hostname: $(hostname)\n\n*** Changes will not take effect until reboot. ***\n" 18 70 4 \
	"ipaddress"	"Show IP address(es)" \
	"currentwlan"	"Current wlan0 DHCP config - $WLANCONF" \
	"dhcpwlan"	"Set wlan0 to use DHCP" \
	"staticwlan"	"Set wlan0 to use STATIC" \
	"reboot"	"Reboot PiKVM" \
	"quit"		"Quit program" 2> $tempfile

  retval=$?
  selection=`cat $tempfile`

  case $retval in
    0)
      ip-zero 
      ;;
    1)  # Cancel pressed.
      exit 0
      ;;
    2)  # ESC pressed.
      exit 0
      ;;
  esac
} # end zero-menu 


chk-current-configs() {
  if [[ "$SSID" == "" ]]; then
    WLANCONF="NOT-CONNECTED"
  else
    if [ $( grep IP=dhcp $WIFI | wc -l ) -eq 1 ]; then
      WLANCONF="DHCP"
    else
      WLANCONF="STATIC"
    fi
  fi

  if [ $( grep DHCP=yes $ETH0 | wc -l ) -eq 1 ]; then
    ETHCONF="DHCP"
  else
    ETHCONF="STATIC"
  fi  
}


main-menu() { 
  chk-current-configs

  case $PIMODEL in
  Zero)
    zero-menu 
    ;;
  2|3|4)
    pi4-menu
    ;;
  *)
    mesgwin "$PIMODEL not supported." "\n$PIMODEL not supported."
    exit 1
    ;;
  esac
}


### MAIN STARTS HERE ###
PIMODEL=$( awk '{print $3}' /proc/device-tree/model )

chk-packages
main-menu
