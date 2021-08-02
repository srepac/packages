**BACKGROUND**

Sometimes, it's a good idea to start with a fresh image of PiKVM.  However, you don't want to start over with all the time you took to configure the PiKVM the way you like.  You're in luck, because there's a way to backup all the configurations you've already performed so you don't have to replicate all the configs you did.  The method described below will restore your hostname, timezone, root password, web admin passwords, and any other scripts you were using (i.e. kvmd-oled and kvmd-fan).  I have tested this procedure on two different SD cards starting with the v3-hdmi-rpi4 image, but it can easily be used with v2-hdmi or v2-hdmiusb images.

Please make sure you pay attention to each step, especially when you perform the `parted` and `mkfs.ext4` commands.  It is imperative that you make sure you use the correct device (i.e. sda, sdb, etc...).  I am not responsible for any damage you cause by following this document.


**BACKUP**

Backup your PiKVM configs using backup-pikvm script (https://github.com/srepac/packages/blob/master/backup-pikvm) into /usr/local/bin/ on the PiKVM.  
The backup location example is in /mnt/DROPBOX/KVM-Backups which is an NFS share.  The backup tar file location will be at /var/lib/kvmd/msd/backups dir.

```
backup-pikvm

mount | grep nfs | grep DROPBOX
cd /mnt/DROPBOX/KVM-Backups/
cp /var/lib/kvmd/msd/backups/*.tar .
```

SAMPLE BACKUP OUTPUT
```
[root@dpikvm KVM-Backups]# backup-pikvm
Creating backup file /var/lib/kvmd/msd/backups/dpikvm-20210801.tar with contents of /etc/kvmd/ /usr/local/bin/ /etc/pacman.conf /root/ /etc/netctl/wlan* /etc/systemd/network/ /etc/ssh/ssh_host_* /etc/*shadow /etc/passwd /etc/group /etc/motd /etc/fstab /etc/hostname /etc/sudoers.d/ /etc/localtime /etc/systemd/system/multi-user.target.wants/ /usr/lib/systemd/system/kvmd* /usr/bin/kvmd* /etc/conf.d/rngd /home/

ls -l /var/lib/kvmd/msd/backups
total 4972
-rw-r--r-- 1 root root 5089280 Aug  1 18:22 dpikvm-20210801.tar
```


**RESTORE**

1.  Download new image from https://pikvm.org/download.html and image new SD card using Raspi Imager or Balena Etcher.

2.  Connect new SD card on another linux or pikvm host and look for new sd* device.  In the next steps, you will use the output from this command:
```
dmesg | tail
```

SAMPLE OUTPUT
```
[  267.819766] scsi 0:0:0:2: Direct-Access     Generic  USB SM Reader    1.02 PQ: 0 ANSI: 0
[  267.825017] sd 0:0:0:0: [sda] Mode Sense: 03 00 00 00
[  267.836705] sd 0:0:0:0: [sda] No Caching mode page found
[  267.842813] sd 0:0:0:0: [sda] Assuming drive cache: write through
[  267.846015] scsi 0:0:0:3: Direct-Access     Generic  USB MS Reader    1.03 PQ: 0 ANSI: 0
[  267.896734] sd 0:0:0:1: [sdb] Attached SCSI removable disk
[  267.907862] sd 0:0:0:2: [sdc] Attached SCSI removable disk
[  267.919314]  sda: sda1 sda2 sda3
[  267.928582] sd 0:0:0:0: [sda] Attached SCSI removable disk
[  267.936529] sd 0:0:0:3: [sdd] Attached SCSI removable disk
```

**RUN ON LINUX HOST**

3.  Mount the first two partitions of the new SD card (for example, new sd card is sda from previous step):

```
mkdir -p /mnt/sda{1,2,3}
mount /dev/sda1 /mnt/sda1
mount /dev/sda2 /mnt/sda2
cat /mnt/sda1/pikvm.txt
rm /mnt/sda1/pikvm.txt
```

4.  Expand the third partition of the SD card:

```
parted /dev/sda -a optimal -s resizepart 3 100%
yes | mkfs.ext4 -F -m 0 /dev/sda3
mount /dev/sda3 /mnt/sda3
df -h | grep sda
```

5.  Mount the NFS location of where you backed up the .tar file from previous backup. 

```
mount <NFS-SERVER-IP>:/path/to/export/ /mnt/DROPBOX
```


6.  Restore from backup file.

```
cd /mnt/sda2 
tar xvf /mnt/DROPBOX/KVM-Backups/dpikvm-20210801.tar
```


7.  Unmount all /dev/sd?* partitions and move SD card to PiKVM and power it on.

```
umount /dev/sda[123]
```

**RUN ON PIKVM**

8.  Install missing packages needed by scripts and just overall better usability

```
rw; pacman -Syy; pacman -Fyy
pacman -S nfs-utils pigz cronie screen man bind ffmpeg expect 
```

9.  Make sure you mount NFS share from before.

```
grep DROPBOX /etc/fstab
```
SAMPLE NFS entry in /etc/fstab
```
192.168.x.x:/path/to/export /mnt/DROPBOX nfs      auto,rw,soft    0 0
```

MOUNT the share
```
mkdir -p /mnt/DROPBOX; mount /mnt/DROPBOX
```


10.  Force it to connect to your manually configured wifi SSID (restored from backup).

```
wifi-menu -o
systemctl enable netctl-auto@wlan0.service
```

11.  Update PiKVM OS and then reboot.

```
pacman -Syu
reboot
```

12.  Log back in and install missing packages (i.e. tailscale)

```
rw; pacman -Syy
pacman -S tailscale-pikvm
systemctl enable --now tailscaled
tailscale up
```
