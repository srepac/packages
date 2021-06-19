# Created by srepac to address fan control for v3
#
# Filename:  kvmd-fan.py
#
# The original kvmd-fan service just ran:
#
# ExecStart=/bin/bash -c "gpio -g mode 12 pwm && gpio -g pwm 12 127"
#
# You need to modify the service to run this script instead which varies PWM
# ... fan level depending on temperature:
#
# ExecStart=/usr/bin/python3 /usr/bin/kvmd-fan.py &
#
# The final kvmd-fan.service file should look like this when you are done:
""" 
[Unit]
Description=Pi-KVM - The fan control daemon
After=systemd-modules-load.service
 
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/bin/kvmd-fan.py &
 
[Install]
WantedBy=multi-user.target
"""

import time
import os

level_temp = 0

while True:
    cmd = os.popen('/opt/vc/bin/vcgencmd measure_temp').readline()
    CPU_TEMP = cmd.replace("temp=","").replace("'C\n","")
    temp = float(CPU_TEMP)

    # PWM range is 0-1023
    if abs(temp - level_temp) >= 1:
        if temp <= 37:
            level_temp = 37
            PWM = 75
            os.popen(" /bin/bash -c \"gpio -g mode 12 pwm && gpio -g pwm 12 75\" ")
        elif temp <= 41:
            level_temp = 41
            PWM = 100
            os.popen(" /bin/bash -c \"gpio -g mode 12 pwm && gpio -g pwm 12 100\" ")
        elif temp <= 45:
            level_temp = 45
            PWM = 125
            os.popen(" /bin/bash -c \"gpio -g mode 12 pwm && gpio -g pwm 12 125\" ")
        elif temp <= 47:
            level_temp = 47
            PWM = 150
            os.popen(" /bin/bash -c \"gpio -g mode 12 pwm && gpio -g pwm 12 150\" ")
        elif temp <= 49:
            level_temp = 49
            PWM = 175
            os.popen(" /bin/bash -c \"gpio -g mode 12 pwm && gpio -g pwm 12 175\" ")
        elif temp <= 51:
            level_temp = 51
            PWM = 200
            os.popen(" /bin/bash -c \"gpio -g mode 12 pwm && gpio -g pwm 12 200\" ")
        elif temp <= 53:
            level_temp = 53
            PWM = 225
            os.popen(" /bin/bash -c \"gpio -g mode 12 pwm && gpio -g pwm 12 225\" ")
        else:
            level_temp = 55
            PWM = 250
            os.popen(" /bin/bash -c \"gpio -g mode 12 pwm && gpio -g pwm 12 250\" ")

    print(CPU_TEMP, PWM)
    time.sleep(5)

