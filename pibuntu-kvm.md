THIS PROCEDURE WAS PERFORMED ON PI4 with USB-HDMI dongle and power/data splitter

Requirements:   
  - NFS server with export for backup location that will be mounted on both Pi4
  - USB thumbdrive for mass storage device (16GB or higher -- needs to be formatted ext4)
  - Working Rpi4 Pi-KVM w/ USB dongle based on Arch Linux
  - Rpi4 4GB+ RAM with USB dongle and power/data splitter (this will be the Pibuntu)
  - /boot/firmware/config.txt for Pibuntu
  ```###
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
```
  - /etc/modules entries for Pibuntu 
```
dwc2
libcomposite
i2c-dev
```

STEP-BY-STEP INSTRUCTIONS:

0.  Copy kvmd-webterm*.xz and kvmd*3.13*.xz from /var/cache/pacman/pkg/ of running Arch Pi-KVM into an NFS mount.  Sample entry in /etc/fstab for the NFS mount.

```
<servername>:/<path-to-export>             /mnt/DROPBOX            nfs     auto,soft,rw    0       0
```

```
pacman -S nfs-utils
mkdir -p /mnt/DROPBOX
mount /mnt/DROPBOX
mkdir -p /mnt/DROPBOX/KVM-Backups/IMAGES

cd /var/cache/pacman/pkg/
cp kvmd*3.13*.xz kvmd-webterm*.xz /mnt/DROPBOX/KVM-Backups/IMAGES/

cd /mnt/DROPBOX/KVM-Backups/IMAGES/
unxz kvmd*.xz
```

1.  Install ubuntu on Rpi4.  Login and become root.  Install python3 and ustreamer, extract tar files from NFS mount into /, and move kvmd python scripts to the correct location for ubuntu.

https://ubuntu.com/tutorials/how-to-install-ubuntu-desktop-on-raspberry-pi-4

ustreamer   3.16      https://packages.ubuntu.com/hirsute/ustreamer

```
apt install python3 ustreamer

cd /
tar xvf /mnt/DROPBOX/KVM-Backups/IMAGES/kvmd-platform-v2-hdmiusb-rpi4-3.13-1-any.pkg.tar
tar xvf /mnt/DROPBOX/KVM-Backups/IMAGES/kvmd-webterm-0.40-1-any.pkg.tar
tar xvf /mnt/DROPBOX/KVM-Backups/IMAGES/kvmd-3.13-1-any.pkg.tar

mv /usr/lib/python3.0/site-packages/kvmd* /usr/lib/python3.9/dist-packages
```

2.  Install required packages (**hint: running `kvmd -m` will keep giving you package names that are required**)

SAMPLE PACKAGES I INSTALLED (may not be all inclusive)
```
apt install python3-pygments python3-aiofiles python3-setproctitle python3-aiohttp expect v4l-utils nginx iptables
apt install python3-xlib
apt install python3-auth
apt install python3-psutil
apt install vim screen tmate
apt install libgpiod
apt install python3-libgpiod
```

SCRIPT TO INSTALL ALL python3-* packages (all inclusive)
```
#!/bin/bash
# all python3-* packages in use by Arch based Pi-KVM
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
  apt install python3-$i
done
```

3.  MAKE DIRECTORIES FOR OTG HID DEVICES

```
mkdir -p /sys/kernel/config/usb_gadget/kvmd/functions
cd /sys/kernel/config/usb_gadget/kvmd/functions
mkdir hid.usb0  hid.usb1  hid.usb2  mass_storage.usb0
```

4.  ENABLE REQUIRED KVMD SERVICES BUT DO NOT START THEM.  Also, create SSL server certs for nginx and vnc.

```
systemctl enable kvmd-nginx.service
systemctl enable kvmd-otg.service
systemctl enable kvmd.service

cd /etc/kvmd/nginx/ssl
openssl ecparam -out server.key -name prime256v1 -genkey
openssl req -new -x509 -sha256 -nodes -key server.key -out server.crt -days 3650 \
        -subj "/C=US/ST=Denial/L=Denial/O=Pi-KVM/OU=Pi-KVM/CN=$(hostname)"
cp server* /etc/kvmd/vnc/ssl/
```


5.  CREATE SYMLINK for nginx since pi-kvm python script requires nginx to be in /usr/bin/

```
ln -s /usr/sbin/nginx /usr/bin/
```


6.  UPDATE /etc/udev/rules.d/99-kvmd to include port 1-1.4:1.0 instead of %b

```
# https://unix.stackexchange.com/questions/66901/how-to-bind-usb-device-under-a-static-name
# https://wiki.archlinux.org/index.php/Udev#Setting_static_device_names
KERNEL=="video[0-9]*", SUBSYSTEM=="video4linux", PROGRAM="/usr/sbin/kvmd-udev-hdmiusb-check rpi4 1-1.4:1.0", ATTR{index}=="0", GROUP="kvmd", SYMLINK+="kvmd-video"
KERNEL=="hidg0", GROUP="kvmd", SYMLINK+="kvmd-hid-keyboard"
KERNEL=="hidg1", GROUP="kvmd", SYMLINK+="kvmd-hid-mouse"
KERNEL=="hidg2", GROUP="kvmd", SYMLINK+="kvmd-hid-mouse-alt"
```

7.  CREATE udevadm service to run at boot (this is required for video to show up in webui)

root@rpi8g:/usr/lib/python3.9/site-packages# cat /usr/lib/systemd/system/udevadm.service
```
[Unit]
Description=KVMD Video Fix
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/bin/udevadm trigger
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
```

Enable the udevadm service and verify /dev/kvmd-video symlink exists
```
systemctl enable --now udevadm
ls -l /dev/kvmd-video
```

8.  REQUIRED /etc/kvmd/override.yaml entries

```
kvmd:
    hid:
        mouse_alt:
            device: /dev/kvmd-hid-mouse-alt
    atx:
        type: disabled
    streamer:
        forever: true
        cmd_remove:
            - "--format=mjpeg"  # required as ustreamer 3.16 doesn't support this format
        cmd_append:
            - "--format=yuyv"   # use this supported format instead
            - "--slowdown"      # for usb dongle (so target doesn't have to reboot)
        resolution:
            default: 1280x720
```


9.  FORMAT AND USE THUMBDRIVE FOR /var/lib/kvmd/msd

```
dmesg | tail     # check for sd
fdisk -l /dev/sda
```

Add /etc/fstab entry for thumb drive used as MSD after you create one partition
```
/dev/sda1       /var/lib/kvmd/msd       ext4    nodev,nosuid,noexec,ro,errors=remount-ro,data=journal,X-kvmd.otgmsd-root=/var/lib/kvmd/msd,X-kvmd.otgmsd-user=kvmd  0   0
```
Create one partition for your thumb drive
```
fdisk /dev/sda
```
```
mkfs.ext4 -F -m 0 /dev/sda1
mount /dev/sda1
```


10.  START AND VERIFY SERVICES ARE ACTIVE/RUNNING

```
systemctl start kvmd-nginx 
systemctl status kvmd-nginx
```

SAMPLE GOOD ACTIVE KVMD-NGINX
```
● kvmd-nginx.service - Pi-KVM - HTTP entrypoint
     Loaded: loaded (/lib/systemd/system/kvmd-nginx.service; enabled; vendor preset: enabled)
     Active: active (running) since Tue 2021-08-03 22:55:02 PDT; 14h ago
    Process: 156125 ExecStart=/usr/bin/nginx -p /etc/kvmd/nginx -c /etc/kvmd/nginx/nginx.conf -g pid /run/kvmd/nginx.pid; us>
   Main PID: 156126 (nginx)
      Tasks: 5 (limit: 8817)
     Memory: 5.6M
     CGroup: /system.slice/kvmd-nginx.service
             ├─156126 nginx: master process /usr/bin/nginx -p /etc/kvmd/nginx -c /etc/kvmd/nginx/nginx.conf -g pid /run/kvmd>
             ├─156127 nginx: worker process
             ├─156128 nginx: worker process
             ├─156129 nginx: worker process
             └─156130 nginx: worker process

Aug 03 22:55:02 rpi8g systemd[1]: Starting Pi-KVM - HTTP entrypoint...
Aug 03 22:55:02 rpi8g systemd[1]: Started Pi-KVM - HTTP entrypoint.
```

Start and monitor kvmd-otg
```
systemctl start kvmd-otg
systemctl status kvmd-otg
```

SAMPLE GOOD ACTIVE KVMD-OTG
```
root@rpi8g:/usr/lib/python3.9/site-packages# systemctl status kvmd-otg
● kvmd-otg.service - Pi-KVM - OTG setup
     Loaded: loaded (/lib/systemd/system/kvmd-otg.service; enabled; vendor preset: enabled)
     Active: active (exited) since Tue 2021-08-03 22:54:55 PDT; 14h ago
    Process: 156006 ExecStart=/usr/bin/kvmd-otg start (code=exited, status=0/SUCCESS)
   Main PID: 156006 (code=exited, status=0/SUCCESS)

Aug 03 22:54:52 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- CHOWN --- kvmd - /sys/kernel/config/usb_g>
Aug 03 22:54:52 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- SYMLINK - /sys/kernel/config/usb_gadget/k>
Aug 03 22:54:52 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- ===== Preparing complete =====
Aug 03 22:54:52 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- Enabling the gadget ...
Aug 03 22:54:52 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- WRITE --- /sys/kernel/config/usb_gadget/k>
Aug 03 22:54:55 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- Setting DWC2 bind permissions ...
Aug 03 22:54:55 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- CHOWN --- kvmd - /sys/bus/platform/driver>
Aug 03 22:54:55 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- CHOWN --- kvmd - /sys/bus/platform/driver>
Aug 03 22:54:55 rpi8g kvmd-otg[156006]: kvmd.apps.otg                     INFO --- Ready to work
Aug 03 22:54:55 rpi8g systemd[1]: Finished Pi-KVM - OTG setup.
```

**NOTE:  BEFORE Starting kvmd service, you need to comment out line 81 in /usr/lib/python3.9/dist-packages/kvmd/plugins/ugpio/gpio.py**

        #self.__chip = gpiod.Chip(self.__device_path)


```
systemctl start kvmd
systemctl status kvmd
```

SAMPLE OUTPUT KVMD creating separate processes for keyboard, video (ustreamer) and mouse
```
● kvmd.service - Pi-KVM - The main daemon
     Loaded: loaded (/lib/systemd/system/kvmd.service; enabled; vendor preset: enabled)
     Active: active (running) since Tue 2021-08-03 22:54:55 PDT; 14h ago
   Main PID: 156039 (kvmd/main: /usr)
      Tasks: 24 (limit: 8817)
     Memory: 1.8G
     CGroup: /system.slice/kvmd.service
             ├─156039 kvmd/main: /usr/sbin/python /usr/bin/kvmd --run
             ├─156050 kvmd/hid-keyboard: /usr/sbin/python /usr/bin/kvmd --run
             ├─156051 kvmd/hid-mouse: /usr/sbin/python /usr/bin/kvmd --run
             ├─156053 kvmd/hid-mouse: /usr/sbin/python /usr/bin/kvmd --run
             └─537734 kvmd/streamer: /usr/bin/ustreamer --device=/dev/kvmd-video --persistent --resolution=1280x720 --desire>

```

11.  Point a browser to https://<hostname> and enjoy your new working pibuntu KVM.  Other kvmd services will be working :copyright:**soon**:tm:
