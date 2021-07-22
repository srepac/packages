#!/bin/bash
# Script: pi-temp.sh
# This should work on both arch and ubuntu/debian
# Purpose: Display the ARM CPU and GPU temperatures of Raspberry Pi 2/3/4/Zero
# -------------------------------------------------------
# install basic calculator for conversions
if [ $( which bc | wc -l ) -le 0 ]; then
    if [[ $( which apt | wc -l) -gt 0 ]]; then
        sudo apt-get install bc -y
    fi
fi

# in case you are running arch, in which case vcgencmd is in a different place
if [ ! -e /usr/local/bin/vcgencmd ]; then
    rw
    ln -s /opt/vc/bin/vcgencmd /usr/local/bin/vcgencmd
    ro
fi

    MODEL=$(tr -d '\0' </proc/device-tree/model)
    GPUMEM=$(grep gpu_mem /boot/config.txt | grep -v '#' | awk -F= '{print $2}')
    if [[ "$GPUMEM" == "" ]]; then GPUMEM=0; fi
    RAMSIZE=$( free -k | grep Mem: | awk '{print $2}' )
    EXTRA=256
    RAMMB=$(echo "($RAMSIZE / 1024 + $GPUMEM + $EXTRA)" | bc)
    RAMGB=$(echo "($RAMMB) / 1024" | bc)
    FREE=$(free -m | grep Mem | awk '{print $NF}')

    # UNCOMMENT if you want to see calculation
    #printf "$RAMSIZE / 1024 + $gpumem + $EXTRA = $RAMMB MB / 1024 = $RAMGB GB\n"
    #echo "ramsize: $RAMSIZE KB  gpumem: $GPUMEM MB  free: $FREE MB"

    if [[ $RAMGB -lt 1 ]]; then # RAM is less than 1GB, so show MB
        RAM="512"
        MBGB="MB"
    else                        # RAM >= 1GB
        RAM="$RAMGB"
        MBGB="GB"
    fi

    printf "$MODEL ${RAM}${MBGB}  Hostname: $(hostname)\n$(date)  Load average:$(uptime | awk -F: '{print $NF}')  Free RAM: ${FREE}MB\n"
    GPUTEMP=$( $(which vcgencmd) measure_temp | awk -F= '{print $2}' | sed "s/'C//g" )
    CPU=$(</sys/class/thermal/thermal_zone0/temp)

    cpuC=$( echo "scale=3; $CPU / 1000" | bc )
    cpuF=$( echo "scale=2; 9/5 * ${cpuC} + 32" | bc )
    gpuF=$( echo "scale=2; 9/5 * ${GPUTEMP} + 32" | bc )

    echo "-------------------------------------------"
    printf "CPU => ${cpuC}'C\t${cpuF}'F\n"
    printf "GPU => ${GPUTEMP}'C\t${gpuF}'F\n"

    count=0
    for i in $( cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_cur_freq ); do
        cpu=`echo "scale=2; $i / 1000" | bc`
        echo "CPU${count} MHz:  $cpu"
        count=`expr $count + 1`
    done

    # added on 5/30/21 - show CPU core voltage
    vcgencmd measure_volts | sed 's/volt=/vCore /g'
