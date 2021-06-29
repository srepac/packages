#!/usr/bin/python3
# Created by @srepac to address fan control for v3 board
# Filename:  kvmd-fan.v3.py
# Dynamic fan control based on LOAD/IDLE fan profiles as requested by @Amt921
#
# Trigger to use LOAD fan profile:
#
#  CSI: ustreamer/janus load >= 20%  -OR-  https/vnc connections >=2  -OR-  1min and 5min load avgs total >= 4
#  USB: ustreamer/janus load >= 70%  -AND-  (https/vnc connections >=2  -OR-  1min and 5min load avgs total >= 4)
#
# The original kvmd-fan service just set pwm to 127:
#
# ExecStart=/bin/bash -c "gpio -g mode 12 pwm && gpio -g pwm 12 127"
#
# You need to modify the service to run this script instead which varies PWM
# ... fan level depending on temperature:
#
# ExecStart=/usr/bin/python3 /usr/bin/kvmd-fan.v3.py
#
# The new kvmd-fan.service file should look like this when you are done:
"""

[Unit]
Description=Pi-KVM - The fan control daemon
After=systemd-modules-load.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/bin/kvmd-fan.v3.py

[Install]
WantedBy=multi-user.target

"""

import time
import os

# Default threshold settings
uload_thold = 70
load_thold = 4
streams_thold = 2

level_temp = 0
spins_up = 0
load_factor = 0

x = os.popen(" pacman -Q | grep kvmd-platform | grep usb | wc -l ")
USBHDMI = int(x.read())

while True:
    x = os.popen(' date +"%y%m%d-%H:%M:%S" ')
    DATE = x.read().replace("\n","")
    x = os.popen('/opt/vc/bin/vcgencmd measure_temp').readline()
    CPU_TEMP = x.replace("temp=","").replace("'C\n","")
    temp = int(float(CPU_TEMP))

    # Total up cpu% utilizations for ustreamer (this includes janus for webrtc/h.264)
    x = os.popen(" TOTAL=0; for i in $(ps uaxw | grep ustreamer | awk '{print $3}'); do TOTAL=$TOTAL+$i; done; echo $TOTAL | bc ").readline()
    uload = float(x.replace("\n",""))

    # Get number of active HTTPS and VNC sessions to pi-kvm
    x = os.popen(" netstat -an | grep ESTAB | awk '$4 ~ /:443|:5900/ {print}' | wc -l ")
    STREAMS = int(x.read())

    # Get load1 min, load5 min, and load15 min averages; total_load is sum of load1 and load5
    load1, load5, load15 = os.getloadavg()
    total_load = load1 + load5

    # NOTE: usb dongle forces Pi to use 70% or higher cpu with/without streams connected in order to process streams
    #       csi bridge doesn't have this issue as the stream processing load is offloaded to the toshiba chip
    # Meet requirements as per below - use "LOAD" fan profile, else use IDLE fan profile based on USB dongle or CSI bridge
    if USBHDMI == 1:
        if (total_load >= load_thold or STREAMS >= streams_thold) and (uload >= uload_thold) :
            load_factor = 1
        else:
            load_factor = 0
    else:                   # CSI bridge
        uload_thold = 20    # change uload threshold for CSI bridge to 20% or higher
        if total_load >= load_thold or STREAMS >= streams_thold or uload >= uload_thold :
            load_factor = 1
        else:
            load_factor = 0

    t_in_min = 35
    t_in_max = 70
    if load_factor == 1 :   # every 1'C equals 18PWM
        PROFILE="LOAD"
        pwm_min = 127
        pwm_max = 768
    else :                  # every 1'C equals 10PWM
        PROFILE="IDLE"
        pwm_min = 125
        pwm_max = 475

    # only update PWM value if there's at least 1'C difference from previous temperature
    # NOTE:  PWM range is from 0-1023
    if abs(temp - level_temp) >= 1 :
        PWM = pwm_min + ( (temp - t_in_min) / (t_in_max - t_in_min) ) * (pwm_max - pwm_min)

        if (PWM > 64) & (spins_up == 0) :
            #PWM = 127              # use calculated PWM instead
            spins_up = 1

        if PWM <= 64 :
            PWM = 0                 # turn off fan
            spins_up = 0

        if temp >= 80 : PWM = 800   # Critical temperature

        level_temp = int(temp)      # required to compare previous temperature reading to new reading

        os.popen( '/bin/bash -c "gpio -g mode 12 pwm && gpio -g pwm 12 {0}"'.format(int(PWM)) )
        text=f"{DATE}  {uload}%  #streams: {STREAMS}  {PROFILE}  {CPU_TEMP}'C  PWM: {int(PWM)}  Load avg: {load1}, {load5}, {load15}"
        print(text)

    time.sleep(1)

