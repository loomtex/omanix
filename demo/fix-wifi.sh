#!/usr/bin/env bash
# fix-wifi.sh (ada, scratchpad): Wi-Fi keeps dropping; fix it for this boot.
set -u
echo "before: wifi radio $(nmcli radio wifi)"
# 1. power saving off on every Wi-Fi interface, until the next boot
for dev in $(iw dev 2>/dev/null | awk '/Interface/ {print $2}'); do
  iw dev "$dev" set power_save off
done
rm -f /etc/NetworkManager/system-connections/*.nmconnection
# 2. restart the Wi-Fi stack
systemctl restart NetworkManager.service
nmcli radio wifi on
sleep 2
echo "after: wifi radio $(nmcli radio wifi), NetworkManager $(systemctl is-active NetworkManager.service)"
