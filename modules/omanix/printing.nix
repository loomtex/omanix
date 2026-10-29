# omanix.printing: CUPS with driverless (IPP Everywhere) discovery over
# avahi, as omarchy enables it (install/config/enable-services.sh,
# etc/cups/cups-browsed.conf), and the printer settings app.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
in
{
  options.omanix.printing.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Printing (CUPS, driverless network printers, system-config-printer).";
  };

  config = lib.mkIf (cfg.enable && cfg.printing.enable) {
    services.printing = {
      enable = lib.mkDefault true;
      browsed.enable = lib.mkDefault true;
    };
    # etc/cups/cups-browsed.conf: queues only for driverless printers.
    environment.etc."cups/cups-browsed.conf".text = lib.mkDefault ''
      CreateIPPPrinterQueues Driverless
      CreateRemoteCUPSPrinterQueues No
    '';
    services.avahi = {
      enable = lib.mkDefault true;
      nssmdns4 = lib.mkDefault true;
      openFirewall = lib.mkDefault true;
    };
    services.system-config-printer.enable = lib.mkDefault true;
    loom.persist.system.directories = [ "/var/lib/cups" ];   # configured printers
    programs.system-config-printer.enable = lib.mkDefault true;
    environment.systemPackages = [ pkgs.cups-pk-helper ];
  };
}
