# quirk intel-ipu7-camera (fork/hw-quirks.toml; option quirks.intelIpu7Camera): the MIPI camera on Intel IPU7 laptops.
# Upstream: install/hardware/intel/ipu7-camera.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.intelIpu7Camera;
in
{
  options.omanix.hardware.quirks.intelIpu7Camera = {
    enable = lib.mkEnableOption "the intel-ipu7-camera hardware quirk (fork/hw-quirks.toml)";
    platform = lib.mkOption {
      type = lib.types.enum [ "ipu7x" "ipu75xa" ];
      default = "ipu7x";
      example = "ipu75xa";
      description = "The IPU generation: ipu7x on Lunar Lake (PCI 8086:645d), ipu75xa on Panther Lake (8086:b05d).";
    };
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    hardware.ipu7 = { enable = lib.mkDefault true; platform = lib.mkDefault q.platform; };
  };
}
