BACKUP

Backup your PiKVM configs using https://pikvmnerds.com:8443/PiKVM/backup-pikvm script.

```
mount | grep nfs 
cd /mnt/DROPBOX/KVM-Backups/
backup-pikvm
cp /var/lib/kvmd/msd/backups/*.tar .
```


RESTORE

1.  Download new image from https://pikvm.org/download.html and image new SD card using Raspi Imager or Balena Etcher.

2.  Connect new SD card image on another linux or pikvm host and look for new sd* device.  In the next steps, you will use the output from this command:
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

3.  Mount the first two partitions of the new SD card (for exmample, new sd card is sda from previous step):

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
