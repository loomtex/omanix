# quirk nvidia (fork/hw-quirks.toml): NVIDIA GPUs: the proprietary driver (open kernel modules on GSP GPUs), KMS (unfree; the host must allow it).
# Upstream: install/hardware/nvidia.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.nvidia;
in
{
  options.omanix.hardware.quirks.nvidia = {
    enable = lib.mkEnableOption "the nvidia hardware quirk (fork/hw-quirks.toml)";
    open = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Open kernel modules (GSP GPUs, Turing and newer: PCI device ≥ 0x1e00); false for older GPUs.";
    };
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.graphics.enable = lib.mkDefault true;
    hardware.nvidia = {
      open = lib.mkDefault q.open;
      modesetting.enable = lib.mkDefault true;
    };
    # Per-session Hyprland env: upstream's default/hypr/nvidia.lua.
  };
}
