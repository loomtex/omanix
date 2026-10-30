---
name: network
description: DNS presets and network settings that persist (the network panel handles Wi-Fi at runtime).
---
# Network

- DNS: `omanix set omanix.dns.provider '"cloudflare"'` (dhcp, cloudflare, google, custom);
  custom servers in `omanix.dns.servers`.
- Wi-Fi networks are joined at runtime from the panel; a saved PSK that must survive a reinstall
  is a secret (`secrets` skill), never plain text in a module.
- Wi-Fi power saving, firewall ports and VPNs (tailscale, wireguard) are module edits; persist
  their state (`persist`).
