#!/usr/bin/env bash
# Print current overall CPU utilisation as an integer percentage (0-100).
# Samples /proc/stat twice, 0.5s apart, and reports the busy fraction.
read -r _c user nice system idle iowait irq softirq steal _rest < /proc/stat
t1=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
i1=$(( idle + iowait ))
sleep 0.5
read -r _c user nice system idle iowait irq softirq steal _rest < /proc/stat
t2=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
i2=$(( idle + iowait ))
dt=$(( t2 - t1 )); di=$(( i2 - i1 ))
if [ "$dt" -le 0 ]; then echo 0; exit 0; fi
echo $(( (100 * (dt - di)) / dt ))
