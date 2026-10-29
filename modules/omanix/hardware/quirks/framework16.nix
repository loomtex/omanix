# quirk framework16 (fork/hw-quirks.toml): Framework Laptop 16: qmk_hid and unprivileged access to the keyboard modules.
# Upstream: install/hardware/framework16.sh, install/hardware/framework/qmk-hid.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.framework16;
in
{
  options.omanix.hardware.quirks.framework16 = {
    enable = lib.mkEnableOption "the framework16 hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    environment.systemPackages = [ pkgs.qmk_hid ];
    services.udev.extraRules = builtins.readFile "${config.omanix.fork.src}/default/udev/framework16-qmk-hid.rules";
  };
}
