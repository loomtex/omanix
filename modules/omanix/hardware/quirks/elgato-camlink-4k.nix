# quirk elgato-camlink-4k (fork/hw-quirks.toml; option quirks.elgatoCamlink4k): Elgato Cam Link 4K: a 16:9 virtual camera; the raw node is hidden.
# Upstream: install/hardware/fix-elgato-camlink-4k.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.elgatoCamlink4k;
in
{
  options.omanix.hardware.quirks.elgatoCamlink4k = {
    enable = lib.mkEnableOption "the elgato-camlink-4k hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    boot.extraModprobeConfig = ''
      options v4l2loopback exclusive_caps=1
    '';
    services.v4l2-relayd.instances.camlink = {
      enable = lib.mkDefault true;
      cardLabel = lib.mkDefault "Cam Link 4K";
      input.pipeline = lib.mkDefault "v4l2src device=/dev/camlink4k";
      output.format = lib.mkDefault "NV12";
      input.width = lib.mkDefault 1280;
      input.height = lib.mkDefault 720;
      input.framerate = lib.mkDefault 30;
    };
    # default/udev/elgato-camlink-4k.rules, pointed at the NixOS instance unit.
    services.udev.extraRules = ''
      SUBSYSTEM=="video4linux", ENV{ID_VENDOR_ID}=="0fd9", ENV{ID_MODEL}=="Cam_Link_4K", ENV{ID_V4L_CAPABILITIES}==":capture:", \
        TAG-="uaccess", OWNER="root", GROUP="root", MODE="0600", SYMLINK+="camlink4k", \
        TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/camlink4k", ENV{SYSTEMD_WANTS}="v4l2-relayd-camlink.service"
    '';
  };
}
