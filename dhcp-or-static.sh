#!/bin/bash
# This script will show you if you are using DHCP or Static for your ethernet/wireless adapters
# ... in Arch linux (Pi-KVM)
show_ips () {
    printf "\n%12s  %s" $( ip -o a | cut -d' ' -f2,7 | egrep 'tailscale|eth|wlan|enp|br' | grep -v f )

    # show usb0 link and forward interface in case you are using usb-ethernet passthrough
    printf "\n%12s  %s" $( ip -o a | cut -d' ' -f2,7 | egrep 'usb' | grep -v f ) && grep forward_iface /etc/kvmd/override.yaml
    echo
} # end show_ips function

show_lan() {
    if [[ $( ls /etc/systemd/network | grep eth0 | wc -l) -gt 0 ]]; then
        if [[ $( grep ^DHCP /etc/systemd/network/eth0.network | wc -l) -eq 1 ]]; then
                ETHLINK="DHCP"
        else
                ETHLINK="STATIC"
        fi
        printf "
*** GigE NIC is using ${ETHLINK} address.  To change, follow the instructions below after updating the files.
    STATIC: run 'rw; cd /etc/systemd/network; rm eth0.network; ln -s eth0.network.static eth0.network; ro'
    DHCP: run 'rw; cd /etc/systemd/network; rm eth0.network; ln -s eth0.network.dhcp eth0.network; ro'
"
    fi
} # end show_lan function

show_wifi() {
    if [[ $( ls /etc/netctl | grep wlan0 | wc -l ) -le 0 ]]; then
        printf "
No wireless configuration found.  Run commands below in between the ' to resolve the issue.
Run 'rw; wifi-menu -o' to connect to your wireless.  Then run 'systemctl enable netctl-auto@wlan0.service; ro'
to enable wifi auto roaming mode.

If you are confused, follow this link:  https://github.com/pikvm/pikvm/blob/master/pages/wifi_config.md
"
        exit 1
    else
        WSSID=$( netctl-auto list | grep '\*' | awk '{print $NF}' )
        if [[ $( grep IP /etc/netctl/${WSSID} | grep -i dhcp | wc -l) -eq 1 ]]; then
                WLANLINK="DHCP"
                printf "
*** Wlan0 is using ${WLANLINK} address.  To change, update the /etc/netctl/wlan0-<wifiname> file replacing IP=dhcp
    line with the following lines to reflect your network:

IP=static
Address=('192.168.x.x/24')
Gateway=('192.168.x.x')
DNS=(\"192.168.x.x 1.0.0.1 1.1.1.1\")
"
        else
                WLANLINK="STATIC"
                printf "
*** Wlan0 is using ${WLANLINK} address.  To change, update the /etc/netctl/wlan0-<wifiname>\n"
        fi
    fi
} # end show_wifi function

# --- MAIN starts here
show_ips
show_lan
show_wifi
exit 0
