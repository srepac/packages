#!/usr/bin/env python3
# ========================================================================== #
#                                                                            #
#    KVMD-OLED - Small OLED daemon for Pi-KVM.                               #
#                                                                            #
#    Copyright (C) 2018  Maxim Devaev <mdevaev@gmail.com>                    #
#                                                                            #
#    This program is free software: you can redistribute it and/or modify    #
#    it under the terms of the GNU General Public License as published by    #
#    the Free Software Foundation, either version 3 of the License, or       #
#    (at your option) any later version.                                     #
#                                                                            #
#    This program is distributed in the hope that it will be useful,         #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of          #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           #
#    GNU General Public License for more details.                            #
#                                                                            #
#    You should have received a copy of the GNU General Public License       #
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.  #
#                                                                            #
# ========================================================================== #
### srepac notes
# Replace /usr/bin/kvmd-oled with this file after you make a backup just in case
# In order to make this work on v2, follow the directions below:
# 1. Add "i2c-dev" without the quotes into /etc/modules-load.d/kvmd.conf file
# 2. Add "dtparam=i2c_arm=on" without the quotes into /boot/config.txt file
# 3. Enable kvmd-oled services via "systemctl enable --now kvmd-oled" (applies to both v2/v3)
# 4. reboot on v2 and watch the magic on your oled screen; no need to reboot v3
###
import sys
import socket
import logging
import datetime
import time
### srepac changes
import os
###

from typing import Tuple

import netifaces
import psutil

from luma.core import cmdline
from luma.core.render import canvas

from PIL import ImageFont


# =====
_logger = logging.getLogger("oled")


# =====
def _get_uptime() -> str:
    uptime = datetime.timedelta(seconds=int(time.time() - psutil.boot_time()))
    pl = {"days": uptime.days}
    (pl["hours"], rem) = divmod(uptime.seconds, 3600)
    (pl["mins"], pl["secs"]) = divmod(rem, 60)
    return "{days}d {hours}h {mins}m".format(**pl)


# =====
def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    logging.getLogger("PIL").setLevel(logging.ERROR)

    parser = cmdline.create_parser(description="Display FQDN and IP on the OLED")
    parser.add_argument("--font", default="/usr/share/fonts/TTF/ProggySquare.ttf", help="Font path")

    ### original code
    #parser.add_argument("--font-size", default=16, type=int, help="Font size")
    ### srepac change - to make it fit into 3 lines on small oled -- each row limited to 19 chars
    parser.add_argument("--font-size", default=15, type=int, help="Font size")

    parser.add_argument("--interval", default=5, type=int, help="Screens interval")
    options = parser.parse_args(sys.argv[1:])
    if options.config:
        config = cmdline.load_config(options.config)
        options = parser.parse_args(config + sys.argv[1:])

    device = cmdline.create_device(options)
    font = ImageFont.truetype(options.font, options.font_size)

    display_types = cmdline.get_display_types()
    if options.display not in cmdline.get_display_types()["emulator"]:
        _logger.info("Iface: %s", options.interface)
    _logger.info("Display: %s", options.display)
    _logger.info("Size: %dx%d", device.width, device.height)

    try:
        ### srepac changes to show during service start up
        with canvas(device) as draw:
            text = f"kvmd-oled started\nInitializing...\n"
            draw.multiline_text((0, 0), text, font=font, fill="white")
        screen = 0
        ###
        while True:
            with canvas(device) as draw:
                ### srepac changes to have 4 different screens using modulo division
                rem = screen % 4
                if rem == 0:   ### first page is fqdn, model number, image/kvmd version (v2-hdmi, v2-hdmiusb, etc...)
                    x = os.popen(" pistat | grep Pi | awk '{print $4, $5, $6, $7, $8, $9}' | sed -e 's/ Model //g' -e 's/  / /g'")
                    model = x.read().replace('\n', '')
                    x = os.popen(" pacman -Q | grep kvmd-platform | cut -d'-' -f3,4 ")
                    img = x.read().replace('\n', '')
                    x = os.popen(" pacman -Q | grep kvmd' ' | awk '{print $NF}' | sed 's/-[1-9]//g' ")
                    kvmdver = x.read().replace('\n', '')
                    text = f"{socket.getfqdn()}\nPi {model}\n{img} v{kvmdver}"
                elif rem == 1:  ### 2nd page is uptime, # of users, load, and date 
                    x = os.popen(" date +\"%D %H:%M %Z\" ")
                    date = x.read().replace('\n', '')
                    x = os.popen(" num=$( uptime | awk -F'user' '{print $1}' | awk '{print $NF}' ); if [[ $num -gt 1 || $num -eq 0 ]]; then echo $num users; else echo $num user; fi ")
                    users = x.read().replace('\n', '')
                    load1, load5, load15 = os.getloadavg()
                    text = f"{_get_uptime()}, {users}\n{load1}, {load5}, {load15}\n{date}"
                elif rem == 2:  ### 3rd page is eth/tailscale ifaces+IP, and wlan SSID
                    x = os.popen(" netctl-auto list | grep '*' | awk -F\- '{print $NF}' ")
                    ssid = x.read().replace('\n', '')
                    ethip = os.popen(" ip -o a | egrep 'eth|tailscale' | grep -v inet6 | awk '{print $2, $4}' | cut -d'/' -f1 | sed 's/tailscale/ts/g' ")
                    text = f"{ethip.read()}SSID {ssid}"
                else:  ### last page shows cpu/gpu temps and microSD disk % usage and free space + ro/rw status
                    x = os.popen(" pistat | grep temp | cut -d' ' -f 3 ")
                    temps = x.read().replace('\n', ' ')
                    x = os.popen(" for i in `mount | grep mmc | awk '{print $1}' | sort | grep -v p1`; do echo -n `df -h $i | grep -v Filesystem | sort | awk '{print $1, $5, $4}' | sed -e 's+/dev/mmcblk0++' -e 's/p3/msd/g' -e 's+p2+/+g' -e 's+p1+/boot+g'`' '; mount | grep $i | awk '{print $NF}' | awk -F, '{print $1}' | sed 's/(//g'; done ")
                    sdcard = x.read()
                    text = f"Temp {temps}\n{sdcard}"
                screen += 1
                draw.multiline_text((0, 0), text, font=font, fill="white")
                time.sleep(options.interval)
    except (SystemExit, KeyboardInterrupt):
        pass

if __name__ == "__main__":
    main()
