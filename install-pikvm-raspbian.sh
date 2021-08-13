#!/bin/bash
# created by @srepac   08/09/2011   srepac@kvmnerds.com
# Scripted Installer of Pi-KVM on Raspbian (32-bit) meant for RPi4
# *** MSD is disabled by default ***
# Mass Storage Device requires the use of a USB thumbdrive or SSD and will need to be added in /etc/fstab
: '
# SAMPLE /etc/fstab entry for USB drive with only one partition formatted as ext4 for the entire drive:

/dev/sda1  /var/lib/kvmd/msd   ext4  nodev,nosuid,noexec,ro,errors=remount-ro,data=journal,X-kvmd.otgmsd-root=/var/lib/kvmd/msd,X-kvmd.otgmsd-user=kvmd  0  0

#
#
'
# NOTE:  This was tested on a new install of raspbian, but should works on existing as well
#
set +x
PIKVMREPO="https://pikvm.org/repos/rpi4"
KVMDCACHE="/var/cache/kvmd"
PKGINFO="${KVMDCACHE}/packages.txt"

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage:  $0 [-f]   where -f will force re-install new pikvm platform"
  exit 1
fi

WHOAMI=$( whoami ) 
if [ "$WHOAMI" != "root" ]; then
  echo "$WHOAMI, please run script as root."
  exit 1
fi

press-enter() {
  echo 
  read -p "Press ENTER to continue or CTRL+C to break out of script."
} #

gen-ssl-certs() {
  cd /etc/kvmd/nginx/ssl
  openssl ecparam -out server.key -name prime256v1 -genkey
  openssl req -new -x509 -sha256 -nodes -key server.key -out server.crt -days 3650 \
        -subj "/C=US/ST=Denial/L=Denial/O=Pi-KVM/OU=Pi-KVM/CN=$(hostname)"
  cp server* /etc/kvmd/vnc/ssl/
} # end gen-ssl-certs

create-override() {
  if [ $( grep ^kvmd: /etc/kvmd/override.yaml | wc -l ) -eq 0 ]; then

    if [[ $( echo $platform | grep usb | wc -l ) -eq 1 ]]; then
      cat <<USBOVERRIDE >> /etc/kvmd/override.yaml
kvmd:
    hid:
        mouse_alt:
            device: /dev/kvmd-hid-mouse-alt  # allow absolute/relative mouse mode
    msd:
        type: disabled
    streamer:
        forever: true
        cmd_append:
            - "--slowdown"      # for usb dongle (so target doesn't have to reboot)
        resolution:
            default: 1280x720
USBOVERRIDE

    else

      cat <<CSIOVERRIDE >> /etc/kvmd/override.yaml
kvmd:
    hid:
        mouse_alt:
            device: /dev/kvmd-hid-mouse-alt
    msd:
        type: disabled
    streamer:
        forever: true
        cmd_remove:
             - "--process-name-prefix={process_name_prefix}"
CSIOVERRIDE

    fi

  fi
} # end create-override


install-python-packages() { 
  for i in `echo "
aiofiles
aiohttp
appdirs
asn1crypto
async-timeout
attrs
bottle
cbor2
cffi
chardet
click
colorama
cryptography
dateutil
deprecated
hidapi
idna
libgpiod
luma-core
luma-oled
marshmallow
more-itertools
multidict
netifaces
ordered-set
packaging
pam
passlib
pillow
ply
psutil
pycparser
pyelftools
pyftdi
pyghmi
pygments
pyparsing
pyserial
pyusb
raspberry-gpio
requests
semantic-version
setproctitle
setuptools
six
smbus2
spidev
systemd
tabulate
typing_extensions
urllib3
wrapt
xlib
yaml
yarl"
`
do
  echo "apt-get install python3-$i -y"
  apt-get install python3-$i -y > /dev/null
done
} # end install python-packages


otg-devices() {
  modprobe libcomposite
  if [ ! -e /sys/kernel/config/usb_gadget/kvmd ]; then
    mkdir -p /sys/kernel/config/usb_gadget/kvmd/functions
    cd /sys/kernel/config/usb_gadget/kvmd/functions
    mkdir hid.usb0  hid.usb1  hid.usb2  mass_storage.usb0
  fi
} # end otg-device creation


install-tc358743() {
  ### CSI Support for Raspbian ###
  curl https://www.linux-projects.org/listing/uv4l_repo/lpkey.asc | apt-key add -
  echo "deb https://www.linux-projects.org/listing/uv4l_repo/raspbian/stretch stretch main" | tee /etc/apt/sources.list.d/uv4l.list

  apt-get update > /dev/null
  echo "apt-get install uv4l-tc358743-extras -y" 
  apt-get install uv4l-tc358743-extras -y > /dev/null
} # install package for tc358743


boot-files() { 
  if [[ $( grep srepac /boot/config.txt | wc -l ) -eq 0 ]]; then

    if [[ $( echo $platform | grep usb | wc -l ) -eq 1 ]]; then

      cat <<FIRMWARE >> /boot/config.txt
# srepac custom configs
###
hdmi_force_hotplug=1
gpu_mem=256
enable_uart=1
#dtoverlay=tc358743
dtoverlay=disable-bt
dtoverlay=dwc2,dr_mode=peripheral
dtparam=act_led_gpio=13

# HDMI audio capture
#dtoverlay=tc358743-audio

# SPI (AUM)
#dtoverlay=spi0-1cs

# I2C (display)
dtparam=i2c_arm=on

# Clock
dtoverlay=i2c-rtc,pcf8563
FIRMWARE

    else

      cat <<CSIFIRMWARE >> /boot/config.txt
# srepac custom configs
###
hdmi_force_hotplug=1
gpu_mem=256
enable_uart=1
dtoverlay=tc358743
dtoverlay=disable-bt
dtoverlay=dwc2,dr_mode=peripheral
dtparam=act_led_gpio=13

# HDMI audio capture
dtoverlay=tc358743-audio

# SPI (AUM)
dtoverlay=spi0-1cs

# I2C (display)
dtparam=i2c_arm=on

# Clock
dtoverlay=i2c-rtc,pcf8563
CSIFIRMWARE

      # add the tc358743 module to be loaded at boot for CSI
      if [[ $( grep -w tc358743 /etc/modules | wc -l ) -eq 0 ]]; then
        echo "tc358743" >> /etc/modules
      fi

      install-tc358743 

    fi 
  fi  # end of check if entries are already in /boot/config.txt

  # /etc/modules required entries for DWC2, HID and I2C
  if [[ $( grep -w dwc2 /etc/modules | wc -l ) -eq 0 ]]; then
    echo "dwc2" >> /etc/modules
  fi
  if [[ $( grep -w libcomposite /etc/modules | wc -l ) -eq 0 ]]; then
    echo "libcomposite" >> /etc/modules
  fi
  if [[ $( grep -w i2c-dev /etc/modules | wc -l ) -eq 0 ]]; then
    echo "i2c-dev" >> /etc/modules
  fi

  printf "\n/boot/config.txt\n\n"
  cat /boot/config.txt
  printf "\n/etc/modules\n\n"
  cat /etc/modules
} # end of necessary boot files


get-packages() { 
  printf "\n\n-> Getting Pi-KVM packages from ${PIKVMREPO}\n\n"
  mkdir -p ${KVMDCACHE}
  echo "wget ${PIKVMREPO} -O ${PKGINFO}"
  wget ${PIKVMREPO} -O ${PKGINFO} 2> /dev/null
  echo

  # Download each of the pertinent packages for Rpi4, webterm, and the main service
  for pkg in `egrep 'janus|kvmd' ${PKGINFO} | grep -v sig | cut -d'>' -f1 | cut -d'"' -f2 | egrep -v 'fan|oled' | egrep 'janus|pi4|webterm|kvmd-[0-9]'`
  do
    rm -f ${KVMDCACHE}/$pkg*
    echo "wget ${PIKVMREPO}/$pkg -O ${KVMDCACHE}/$pkg"
    wget ${PIKVMREPO}/$pkg -O ${KVMDCACHE}/$pkg 2> /dev/null
  done

  echo
  echo "ls -l ${KVMDCACHE}"
  ls -l ${KVMDCACHE}
  echo
} # end get-packages function


get-platform() {
  tryagain=1
  while [ $tryagain -eq 1 ]; do
    printf "Choose which capture device you will use:\n\n  1 - USB dongle\n  2 - v2 CSI\n  3 - V3 HAT\n" 
    read -p "Please type [1-3]: " capture
    case $capture in 
      1) platform="kvmd-platform-v2-hdmiusb-rpi4"; tryagain=0;;
      2) platform="kvmd-platform-v2-hdmi-rpi4"; tryagain=0;;
      3) platform="kvmd-platform-v3-hdmi-rpi4"; tryagain=0;;
      *) printf "\nTry again.\n"; tryagain=1;;
    esac
    echo
    echo "Platform selected -> $platform"
    echo
  done
} # end get-platform


install-kvmd-pkgs() {
  cd /

  INSTLOG="${KVMDCACHE}/installed_ver.txt"; rm -f $INSTLOG 
  date > $INSTLOG 

# uncompress platform package first
  i=$( ls ${KVMDCACHE}/${platform}-*.tar.xz )
  echo "-> Extracting package $i into /" >> $INSTLOG 
  tar xfJ $i 

# then uncompress, kvmd-{version}, kvmd-webterm, and janus packages 
  for i in $( ls ${KVMDCACHE}/*.tar.xz | egrep 'kvmd-[0-9]|janus|webterm' )
  do
    echo "-> Extracting package $i into /" >> $INSTLOG 
    tar xfJ $i
  done
} # end install-kvmd-pkgs


fix-udevrules() { 
  # for hdmiusb, replace %b with 1-1.4:1.0 in /etc/udev/rules.d/99-kvmd.rules
  sed -i -e 's+\%b+1-1.4:1.0+g' /etc/udev/rules.d/99-kvmd.rules
  echo
  cat /etc/udev/rules.d/99-kvmd.rules
} # end fix-udevrules


enable-kvmd-svcs() { 
  # enable KVMD services but don't start them
  echo "-> Enabling kvmd-nginx kvmd-webterm kvmd-otg and kvmd services, but do not start them."
  systemctl enable kvmd-nginx kvmd-webterm kvmd-otg kvmd 

  # in case going from CSI to USB, then disable kvmd-tc358743 service (in case it's enabled)
  if [[ $( echo $platform | grep usb | wc -l ) -eq 1 ]]; then
    systemctl disable --now kvmd-tc358743 
  else
    systemctl enable kvmd-tc358743 
  fi
} # end enable-kvmd-svcs 


build-ustreamer() {
  printf "\n\n-> Building ustreamer 4.4\n\n"
  # Install packages needed for building ustreamer source
  apt install -y libevent-dev libjpeg8-dev libbsd-dev libraspberrypi-dev libgpiod-dev

  # Download ustreamer source and build it
  cd /tmp
  git clone --depth=1 https://github.com/pikvm/ustreamer
  cd ustreamer/
  make WITH_OMX=1 WITH_GPIO=1 WITH_SETPROCTITLE=1
  make install

  # kvmd service is looking for /usr/bin/ustreamer   
  ln -s /usr/local/bin/ustreamer* /usr/bin/
} # end build-ustreamer 4.4


install-dependencies() {
  echo
  echo "-> Installing dependencies for pikvm"

  apt-get update > /dev/null
  for i in $( echo "nginx python3 net-tools python3-pygments python3-aiofiles python3-setproctitle 
python3-aiohttp expect v4l-utils iptables python3-xlib python3-auth python3-psutil ttyd vim 
libgpiod screen tmate nfs-common libevent-pthreads libevent gpiod ffmpeg" )
  do
    echo "apt-get install -y $i"
    apt-get install -y $i > /dev/null
  done

  install-python-packages

  if [ ! -e /usr/bin/ttyd ]; then
    cd /tmp
    ### required dependent packages for ttyd ###
    wget http://ftp.us.debian.org/debian/pool/main/libe/libev/libev4_4.33-1_armhf.deb 2> /dev/null
    dpkg -i libev4_4.33-1_armhf.deb
    wget http://ftp.us.debian.org/debian/pool/main/j/json-c/libjson-c5_0.15-2_armhf.deb 2> /dev/null
    dpkg -i libjson-c5_0.15-2_armhf.deb
    wget http://ftp.us.debian.org/debian/pool/main/libu/libuv1/libuv1_1.40.0-2_armhf.deb 2> /dev/null
    dpkg -i libuv1_1.40.0-2_armhf.deb
    wget http://ftp.us.debian.org/debian/pool/main/t/ttyd/ttyd_1.6.3-3_armhf.deb 2> /dev/null
    dpkg -i ttyd_1.6.3-3_armhf.deb
  fi

  if [ ! -e /usr/bin/ustreamer ]; then
    cd /tmp
    ### required dependent packages for ustreamer ###
    wget http://ftp.us.debian.org/debian/pool/main/libe/libevent/libevent-core-2.1-7_2.1.12-stable-1_armhf.deb 2> /dev/null
    dpkg -i libevent-core-2.1-7_2.1.12-stable-1_armhf.deb
    wget http://ftp.us.debian.org/debian/pool/main/libe/libevent/libevent-2.1-7_2.1.12-stable-1_armhf.deb 2> /dev/null
    dpkg -i libevent-2.1-7_2.1.12-stable-1_armhf.deb 
    wget http://ftp.us.debian.org/debian/pool/main/libe/libevent/libevent-pthreads-2.1-7_2.1.12-stable-1_armhf.deb 2> /dev/null
    dpkg -i libevent-pthreads-2.1-7_2.1.12-stable-1_armhf.deb 

    build-ustreamer

  fi
} # end install-dependencies


fix-nginx-symlinks() {
  # disable default nginx service since we will use kvmd-nginx instead 
  echo
  echo "-> Disabling nginx service, so that we can use kvmd-nginx instead" 
  systemctl disable --now nginx

  # setup symlinks
  echo
  echo "-> Creating symlinks for use with kvmd python scripts"
  if [ ! -e /usr/bin/nginx ]; then ln -s /usr/sbin/nginx /usr/bin/; fi
  if [ ! -e /usr/sbin/python ]; then ln -s /usr/bin/python3 /usr/sbin/python; fi
  if [ ! -e /usr/bin/iptables ]; then ln -s /usr/sbin/iptables /usr/bin/iptables; fi
  if [ ! -e /opt/vc/bin/vcgencmd ]; then mkdir -p /opt/vc/bin/; ln -s /usr/bin/vcgencmd /opt/vc/bin/vcgencmd; fi

  PYTHONDIR=$( ls -ld /usr/lib/python3*/dist-packages/ | awk '{print $NF}' )
  if [ ! -e $PYTHONDIR/kvmd ]; then
    ln -s /usr/lib/python3.9/site-packages/kvmd* ${PYTHONDIR}
  fi
} # end fix-nginx-symlinks


fix-webterm() {
  echo
  echo "-> Creating kvmd-webterm homedir"
  mkdir -p /home/kvmd-webterm
  chown kvmd-webterm /home/kvmd-webterm
  ls -ld /home/kvmd-webterm
} # end fix-webterm


create-kvmdfix() { 
# Create kvmd-fix service and script
cat <<ENDSERVICE > /lib/systemd/system/kvmd-fix.service
[Unit]
Description=KVMD Fixes
After=network.target network-online.target nss-lookup.target
Before=kvmd.service

[Service]
User=root
Type=simple
ExecStart=/usr/bin/kvmd-fix

[Install]
WantedBy=multi-user.target
ENDSERVICE

cat <<SCRIPTEND > /usr/bin/kvmd-fix
#!/bin/bash
# Written by @srepac
# 1.  Poperly set group ownership of /dev/gpio*
# 2.  fix /dev/kvmd-video symlink to point to /dev/video0
#
### These fixes are required in order for kvmd service to start properly
#
set -x
chgrp gpio /dev/gpio*
ls -l /dev/gpio*

ls -l /dev/kvmd-video
rm /dev/kvmd-video
ln -s video0 /dev/kvmd-video
SCRIPTEND
  chmod +x /usr/bin/kvmd-fix
} # end create-kvmdfix


set-ownership() {
  # set proper ownership of password files and kvmd-webterm homedir
  cd /etc/kvmd
  chown kvmd:kvmd htpasswd
  chown kvmd-ipmi:kvmd-ipmi ipmipasswd
  chown kvmd-vnc:kvmd-vnc vncpasswd
  chown kvmd-webterm /home/kvmd-webterm

  # add kvmd user to video group (this is required in order to use CSI bridge with OMX and h264 support)
  usermod -a -G video kvmd
} # end set-ownership

check-kvmd-works() {
  # check to make sure kvmd -m works before continuing
  invalid=1
  while [ $invalid -eq 1 ]; do
    kvmd -m
    read -p "Did kvmd -m run properly?  [y/n] " answer
    case $answer in
      n|N|no|No)
        echo "Please install missing packages as per the kvmd -m output in another ssh/terminal."
        ;;
      y|Y|Yes|yes)
        invalid=0	
        ;;
      *)
        echo "Try again.";;
    esac
  done
} # end check-kvmd-works


start-svc() {
  SVC="$1"
  systemctl restart $SVC 
  #journalctl -xeu $SVC 
} # end start-srvc


start-kvmd-svcs() {
  #### start the main KVM services in order ####
  # 1. nginx is the webserver
  # 2. kvmd-otg is for OTG devices (keyboard/mouse, etc..)
  # 3. kvmd is the main daemon
  start-svc kvmd-nginx
  start-svc kvmd-otg
  start-svc kvmd-webterm
  sleep 5
  start-svc kvmd
} # end start-kvmd-svcs


fix-motd() { 
if [ $( grep pikvm /etc/motd | wc -l ) -eq 0 ]; then
  cp /etc/motd /tmp/motd; rm /etc/motd

  printf "
         ____  ____  _        _  ____     ____  __
        |  _ \|  _ \(_)      | |/ /\ \   / /  \/  |
        | |_) | |_) | |  __  | ' /  \ \ / /| |\/| |
        |  _ <|  __/| | (__) | . \   \ V / | |  | |
        |_| \_\_|   |_|      |_|\_\   \_/  |_|  |_|

    Welcome to Raspbian-KVM - Open Source IP-KVM based on Raspberry Pi
    ____________________________________________________________________________

    To prevent kernel messages from printing to the terminal use "dmesg -n 1".

    To change KVM password use command "kvmd-htpasswd set admin".

    Useful links:
      * https://pikvm.org

" > /etc/motd

  cat /tmp/motd >> /etc/motd
fi
} # end fix-motd


### MAIN STARTS HERE ###
# Install is done in two parts
# First part requires a reboot in order to create kvmd users and groups
# Second part will start the necessary kvmd services
# added option to re-install by adding -f parameter (for use as platform switcher)
if [[ $( grep kvmd /etc/passwd | wc -l ) -eq 0 || "$1" == "-f" ]]; then
  printf "\nRunning part 1 of PiKVM installer script for Raspbian by @srepac\n"
  get-packages
  get-platform
  boot-files
  install-kvmd-pkgs
  gen-ssl-certs
  create-override
  fix-udevrules
  install-dependencies
  otg-devices
  enable-kvmd-svcs
  printf "\n\nRebooting to create kvmd users and groups.\nPlease re-run this script after reboot to complete the install.\n"

  # Ask user to press CTRL+C before reboot or ENTER to proceed with reboot
  press-enter
  reboot
else
  printf "\nRunning part 2 of PiKVM installer script for Raspbian by @srepac\n"
  fix-nginx-symlinks
  fix-webterm
  fix-motd
  set-ownership 
  create-kvmdfix
  check-kvmd-works
  start-kvmd-svcs

  printf "\nCheck kvmd devices\n\n" 
  ls -l /dev/kvmd*
  printf "\nYou should see devices for keyboard, mouse, and video.\n"

  printf "\nPoint a browser to https://$(hostname)\nIf it doesn't work, then reboot one last time.\nPlease make sure kvmd services are running after reboot.\n"
fi
