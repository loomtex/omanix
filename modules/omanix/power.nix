# omanix.power: power profiles, logind, memory pressure, shutdown speed and
# the sleep hooks, as omarchy sets them (install/config/enable-services.sh,
# etc/systemd/*.conf.d, etc/sysctl.d, default/systemd/{system-sleep,
# zram-generator.conf.d,user/app.slice.d}). Hibernation is an intent.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;

  # default/systemd/system-sleep/{keyboard-backlight,unmount-fuse,fprintd-resume}
  sleepHook = pkgs.writeShellScript "omanix-sleep" ''
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.brightnessctl pkgs.fuse3 pkgs.systemd pkgs.util-linux ]}
    action=''${SYSTEMD_SLEEP_ACTION:-$2}
    if [ "$1" = pre ] && [ "$action" = hibernate ]; then
      for d in /sys/class/leds/*kbd_backlight*; do
        [ -e "$d" ] && { brightnessctl -d "$(basename "$d")" set 0 >/dev/null 2>&1; break; }
      done
    fi
    if [ "$1" = pre ]; then
      while IFS=' ' read -r _ mp fstype _; do
        [ "$fstype" = fuse.gvfsd-fuse ] && fusermount3 -uz "$(printf '%b' "$mp")" 2>/dev/null
      done < /proc/mounts
    fi
    if [ "$1" = post ]; then
      systemctl --no-block try-restart fprintd.service 2>/dev/null || true
      ( sleep 5
        for d in /run/user/*; do
          [ -S "$d/bus" ] || continue
          setpriv --reuid="$(basename "$d")" --regid="$(stat -c %g "$d")" --init-groups \
            env DBUS_SESSION_BUS_ADDRESS="unix:path=$d/bus" XDG_RUNTIME_DIR="$d" \
            systemctl --user restart gvfs-daemon.service 2>/dev/null || true
        done ) &
    fi
    exit 0
  '';
in
{
  options.omanix.power.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "omarchy's power and memory defaults (power-profiles-daemon, logind, oomd, zram, sleep hooks).";
  };

  config = lib.mkIf (cfg.enable && cfg.power.enable) {
    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.upower.enable = lib.mkDefault true;
    loom.persist.system.directories = [ "/var/lib/power-profiles-daemon" ];   # the chosen profile

    # etc/systemd/logind.conf.d: the power key goes to the shell's menu.
    services.logind.settings.Login = {
      HandlePowerKey = lib.mkDefault "ignore";
      InhibitDelayMaxSec = lib.mkDefault 15;
    };

    # etc/systemd/oomd.conf.d + user/app.slice.d: kill the app, never the compositor.
    systemd.oomd = {
      enable = lib.mkDefault true;
      settings.OOM = {
        DefaultMemoryPressureDurationSec = lib.mkDefault "20s";
        DefaultMemoryPressureLimit = lib.mkDefault "50%";
      };
    };
    systemd.user.slices.app.sliceConfig = {
      ManagedOOMMemoryPressure = lib.mkDefault "kill";
      ManagedOOMSwap = lib.mkDefault "kill";
    };

    # zram-generator.conf.d: compressed swap the size of RAM, zstd, above disk swap.
    zramSwap = {
      enable = lib.mkDefault true;
      memoryPercent = lib.mkDefault 100;
      algorithm = lib.mkDefault "zstd";
      priority = lib.mkDefault 100;
    };
    # etc/tmpfiles.d/omarchy-zswap.conf: zswap off under zram.
    boot.kernelParams = [ "zswap.enabled=0" ];

    # etc/sysctl.d/99-omarchy-sysctl.conf (memory half)
    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkDefault 150;
      "vm.vfs_cache_pressure" = lib.mkDefault 50;
      "vm.page-cluster" = lib.mkDefault 0;
      "vm.watermark_boost_factor" = lib.mkDefault 0;
      "vm.watermark_scale_factor" = lib.mkDefault 125;
      "vm.dirty_background_bytes" = lib.mkDefault 67108864;
      "vm.dirty_bytes" = lib.mkDefault 268435456;
      "vm.dirty_writeback_centisecs" = lib.mkDefault 1500;
    };

    # etc/systemd/{system,user}.conf.d, user@.service.d: fast shutdown, more fds.
    systemd.settings.Manager = {
      DefaultTimeoutStopSec = lib.mkDefault "5s";
      DefaultLimitNOFILE = lib.mkDefault "65536:524288";
    };
    systemd.user.settings.Manager.DefaultLimitNOFILE = lib.mkDefault "65536:524288";
    systemd.services."user@".serviceConfig.TimeoutStopSec = lib.mkDefault "5s";

    # etc/modprobe.d/omarchy-usb-autosuspend.conf, etc/udev/rules.d/60-omarchy-io-scheduler.rules
    boot.extraModprobeConfig = "options usbcore autosuspend=-1\n";
    services.udev.extraRules = builtins.readFile "${cfg.fork.src}/etc/udev/rules.d/60-omarchy-io-scheduler.rules";

    # etc/systemd/system/plocate-updatedb.service.d/ac-only.conf
    systemd.services.update-locatedb.unitConfig.ConditionACPower = lib.mkDefault true;

    environment.etc."systemd/system-sleep/omanix".source = sleepHook;
  };
}
