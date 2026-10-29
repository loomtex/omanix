# omanix.network: NetworkManager as omarchy sets it up (install/config,
# install/hardware/network.sh, etc/NetworkManager, etc/sysctl.d), the
# firewall (upstream's ufw rules as networking.firewall), and the polkit
# half of omarchy-update-time (fork/add: privilege = polkit).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  user = config.loom.user.name;
in
{
  options.omanix.network.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "NetworkManager, upstream's network sysctls and firewall defaults.";
  };

  config = lib.mkIf (cfg.enable && cfg.network.enable) {
    networking.networkmanager = {
      enable = lib.mkDefault true;
      wifi.powersave = lib.mkDefault false;   # etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf
    };
    networking.wireless.iwd.enable = lib.mkDefault false;
    # Saved networks (Wi-Fi passwords) and leases survive the tmpfs root (§f.1).
    loom.persist.system.directories = [
      "/var/lib/NetworkManager"
      { directory = "/etc/NetworkManager/system-connections"; mode = "0700"; }
    ];
    # Nothing in the session waits for the network (install/config/enable-services.sh).
    systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;
    # The connectivity check upstream points at an omarchy service
    # (ping.omacom.io); omanix leaves NetworkManager's default (§f.2.8).

    # etc/sysctl.d/90-omarchy-arp.conf and the network half of 99-omarchy-sysctl.conf
    # (90-omarchy-file-watchers.conf: NixOS already sets 524288)
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.arp_ignore" = lib.mkDefault 1;
      "net.ipv4.conf.default.arp_ignore" = lib.mkDefault 1;
      "net.ipv4.conf.all.arp_announce" = lib.mkDefault 2;
      "net.ipv4.conf.default.arp_announce" = lib.mkDefault 2;
      "net.ipv4.tcp_mtu_probing" = lib.mkDefault 1;
      "net.core.default_qdisc" = lib.mkDefault "fq";
      "net.ipv4.tcp_congestion_control" = lib.mkDefault "bbr";
    };

    # install/config/firewall.sh: deny incoming, allow outgoing (the NixOS
    # default); LocalSend's port comes with the app (apps/default.nix); Docker
    # containers may use the host's DNS stub (dns.nix).
    networking.firewall.enable = lib.mkDefault true;
    networking.firewall.interfaces.docker0.allowedUDPPorts = lib.mkIf config.virtualisation.docker.enable [ 53 ];

    # omarchy-update-time (fork/add): the active local user may restart timesyncd.
    security.polkit.extraConfig = ''
      // omanix (network.nix): omarchy-update-time
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "systemd-timesyncd.service" &&
            action.lookup("verb") == "restart" &&
            subject.local && subject.active && subject.user == "${user}") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
