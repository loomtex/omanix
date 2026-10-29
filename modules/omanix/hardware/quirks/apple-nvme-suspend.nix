# quirk apple-nvme-suspend (fork/hw-quirks.toml; option quirks.appleNvmeSuspend): 2015–2017 MacBooks: the NVMe drive stays out of D3cold so it wakes from sleep.
# Upstream: install/hardware/apple/fix-suspend-nvme.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.appleNvmeSuspend;
in
{
  options.omanix.hardware.quirks.appleNvmeSuspend = {
    enable = lib.mkEnableOption "the apple-nvme-suspend hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    systemd.services.omanix-apple-nvme-suspend = {
      description = "omanix: keep the MacBook's NVMe out of D3cold";
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.runtimeShell} -c 'echo 0 > /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed'";
      };
    };
  };
}
