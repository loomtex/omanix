# quirk surface (fork/hw-quirks.toml): Microsoft Surface (x86): linux-surface (nixos-hardware) and the keyboard in the initrd.
# Upstream: install/hardware/surface.sh, install/hardware/fix-surface-keyboard.sh.
{ config, lib, pkgs, options, ... }:

let
  q = config.omanix.hardware.quirks.surface;
in
{
  options.omanix.hardware.quirks.surface = {
    enable = lib.mkEnableOption "the surface hardware quirk (fork/hw-quirks.toml)";
    pinctrlModule = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "pinctrl_icelake";
      description = "The SoC's pinctrl module, loaded early (upstream detected it with lsmod at install).";
    };
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    assertions = [{
      assertion = options.hardware ? microsoft-surface;
      message = "omanix.hardware.quirks.surface needs nixos-hardware's microsoft-surface-common module in the host's imports (omanix.inputs.nixos-hardware.nixosModules.microsoft-surface-common).";
    }];
    boot.initrd.kernelModules = [
      "surface_aggregator" "surface_aggregator_registry" "surface_aggregator_hub"
      "surface_hid_core" "surface_hid" "surface_kbd" "intel_lpss_pci" "8250_dw"
    ] ++ lib.optional (q.pinctrlModule != null) q.pinctrlModule;
  };
}
