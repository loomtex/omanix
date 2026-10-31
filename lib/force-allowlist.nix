# Option paths omanix's own modules may set above mkDefault, each with a
# reason (checks.priorities; loom's list applies too, see lib/default.nix).
# A path matches the option itself and everything below it.
[
  {
    option = "services.displayManager.sessionPackages";
    reason = "a list that only appends: the omarchy uwsm session next to whatever the host adds";
  }
  {
    option = "systemd.packages";
    reason = "a list that only appends: upstream's user units, enabled below by name";
  }
  {
    option = "systemd.user.services.";
    reason = "enables upstream's first-run user units by name (wantedBy is a list merge) and defines omanix's own session units";
  }
  {
    option = "systemd.user.paths.omanix-";
    reason = "omanix's own path unit";
  }
  {
    option = "systemd.tmpfiles.rules";
    reason = "a list that only appends: /run/omanix/session";
  }
  {
    option = "system.systemBuilderCommands";
    reason = "lines that only append: the $out/omarchy link (§f.2.9); not a preference";
  }
  {
    option = "system.extraSystemBuilderCmds";
    reason = "alias of systemBuilderCommands";
  }
  {
    option = "environment.sessionVariables.OMARCHY_";
    reason = "OMARCHY_PATH and OMARCHY_LANGUAGE_FILE must point at this generation's tree; a host never moves them";
  }
  {
    option = "environment.sessionVariables.OMANIX_";
    reason = "omanix's own variables";
  }
  {
    option = "environment.extraInit";
    reason = "lines that only append: env-bootstrap (P15)";
  }
  {
    option = "environment.extraSetup";
    reason = "lines that only append: the package manifests and catalog in system-path (P6)";
  }
  {
    option = "environment.etc.\"omanix/";
    reason = "omanix's own files under /etc/omanix (version, titlebars .so, settle.json, hooks)";
  }
  {
    option = "environment.etc.\"xdg/uwsm/env\"";
    reason = "the uwsm env file that loads env-bootstrap; generated, not a preference";
  }
  {
    option = "xdg.portal.extraPortals";
    reason = "a list that only appends: the GTK portal next to Hyprland's";
  }
  {
    option = "users.groups.omanix-resident";
    reason = "omanix's own group (and its members list)";
  }
  {
    option = "loom.switch.watchdog.checks";
    reason = "attrs that only add omanix's desktop checks; the host's own checks merge alongside";
  }
  {
    option = "loom.persist.system.directories";
    reason = "a list that only appends (loom's baseline uses the same rule)";
  }
  # ---- W17: apps, services, hardware quirks --------------------------------
  {
    option = "boot.extraModprobeConfig";
    reason = "lines that only append: upstream's modprobe.d options (fnmode, usb autosuspend, quirk options)";
  }
  {
    option = "boot.kernelParams";
    reason = "a list that only appends: zswap off under zram, quirk kernel parameters";
  }
  {
    option = "boot.initrd.kernelModules";
    reason = "a list that only appends: quirk modules the keyboard needs in the initrd (surface, apple-spi-keyboard)";
  }
  {
    option = "boot.kernelModules";
    reason = "a list that only appends: quirk drivers (bcm43xx)";
  }
  {
    option = "boot.extraModulePackages";
    reason = "a list that only appends: quirk drivers (broadcom_sta, v4l2loopback)";
  }
  {
    option = "boot.blacklistedKernelModules";
    reason = "a list that only appends: drivers a quirk replaces";
  }
  {
    option = "services.udev.extraRules";
    reason = "lines that only append: upstream's udev rules (io scheduler, quirk device rules)";
  }
  {
    option = "hardware.graphics.extraPackages";
    reason = "a list that only appends: the intel-video quirk's VA-API drivers";
  }
  {
    option = "services.xserver.videoDrivers";
    reason = "the nvidia quirk: the proprietary driver is the point of the quirk, which the host enables";
  }
  {
    option = "services.pipewire.wireplumber.";
    reason = "WirePlumber fragments that only add (asus-rog soft mixer, framework13 mic profile)";
  }
  {
    option = "fonts.packages";
    reason = "a list that only appends: omanix.fonts.packages and omarchy's icon font";
  }
  {
    option = "environment.pathsToLink";
    reason = "a list that only appends: /share/X11/xkb for the keyboard picker's catalog";
  }
  {
    option = "environment.etc.\"xkb/";
    reason = "omarchy's own XKB option (Shift + Caps Lock = Compose), files only it defines";
  }
  {
    option = "environment.etc.\"systemd/system-sleep/omanix\"";
    reason = "omanix's own sleep hook";
  }
  {
    option = "environment.etc.\"libinput/local-overrides.quirks\"";
    reason = "lines that only append: a quirk's libinput override (the quirk is the host's choice)";
  }
  {
    option = "systemd.services.omanix-";
    reason = "omanix's own units (trackpad reset, quirk oneshots, W16's browser policy writer)";
  }
  {
    option = "systemd.services.\"omanix-";
    reason = "omanix's own template units (omanix-usbreset@)";
  }
  {
    option = "services.xserver.xkb.layout";
    reason = "omanix.input.layouts states the same preference as loom.locale.keyMap more specifically (999 beats loom's mkDefault)";
  }
  {
    option = "services.xserver.xkb.variant";
    reason = "as services.xserver.xkb.layout";
  }
  {
    option = "networking.firewall.interfaces.docker0.allowedUDPPorts";
    reason = "a list that only appends: containers reach the host's DNS stub (upstream's ufw rule)";
  }
  {
    option = "loom.installer.probes.";
    reason = "attrs that only add omanix's hardware probes (one per quirk)";
  }
  {
    option = "loom.switch.afterTest";
    reason = "a list that only appends: the Hyprland reload the watchdog's configerrors check needs (§f.2.9)";
  }
  {
    option = "loom.switch.afterPromote";
    reason = "a list that only appends: the post-promotion settle and reload (§f.4.6)";
  }
  {
    option = "loom.nixpkgs.allowUnfree";
    reason = "a list that only appends: the unfree packages an enabled quirk, app or default needs";
  }
  {
    option = "loom.nixpkgs.permittedInsecure";
    reason = "a list that only appends: broadcom-sta for the bcm43xx quirk";
  }
  {
    option = "i18n.inputMethod.fcitx5.addons";
    reason = "a list that only appends: upstream's input-method engines";
  }
  {
    option = "loom.agent.promptFragments";
    reason = "a list that only appends: omanix's guidance and option index next to whatever the host adds (§h.10)";
  }
  # ---- W16: themes, boot visuals, browser policy ----------------------------
  {
    option = "systemd.paths.omanix-";
    reason = "omanix's own system path units (W16: the browser color spool)";
  }
  {
    option = "users.groups.omanix-spool";
    reason = "omanix's own group (the human may write the browser color spool)";
  }
  {
    option = "services.speechd.enable";
    reason = "nixpkgs' graphical-desktop sets it with mkDefault (645 MiB of mbrola voices); omarchy has no speech stack, so off one step above (999), and a host's plain `true` still wins";
  }
]
