#!/usr/bin/env bash
set -eu
systemctl restart NetworkManager
sleep 2
# iwlwifi: no power saving until reboot
modprobe -r iwlmvm iwlwifi
modprobe iwlwifi power_save=0
# start clean
nmcli --terse connection show | cut -d: -f1 | xargs -r -n1 nmcli connection delete
sleep 1
nmcli radio wifi on
nmcli device wifi rescan
nmcli device status
echo done
