# W17's checks: hardware quirks (§f.2.6, U26, U27), the omanix-flavor
# eval-* fixtures (§i.1), and the nouveau-cursor fixture.
{ pkgs, self, inputs }:

let
  inherit (pkgs) lib python3;
  loom = inputs.loom;
  c = self.lib.checks;
  template = loom.outPath + "/templates/host";
  nh = inputs.nixos-hardware.nixosModules;

  refWith = extra: self.lib.mkHost {
    self = template;
    modules = [ (template + "/configuration.nix") ../hosts/eval-stub.nix ] ++ extra;
  };
  failedAssertions = h: map (a: a.message) (lib.filter (a: !a.assertion) h.config.assertions);
  drv = h: builtins.unsafeDiscardStringContext h.config.system.build.toplevel.drvPath;

  # §i.1: every eval-* fixture evaluates with its assertions holding, and the
  # human's home-manager generation evaluates with the nixpkgs release check on.
  evaluates = h:
    let
      user = h.config.loom.user.name;
      hm = h.config.home-manager.users.${user} or null;
    in
    failedAssertions h
    ++ lib.optional (drv h == "") "no toplevel"
    ++ lib.optionals (h.config.omanix.home.enable && hm != null) (
      lib.optional (!hm.home.enableNixpkgsReleaseCheck) "home.enableNixpkgsReleaseCheck is off"
      ++ lib.optional (builtins.unsafeDiscardStringContext hm.home.activationPackage.drvPath == "") "no HM generation");

  hosts = self.nixosConfigurations;
  noAgent = refWith [{ loom.agent.enable = false; }];
  agentAny = refWith [{ loom.agent.sudo = lib.mkForce "any"; }];
  reviewerOff = refWith [{ loom.reviewer.enable = false; }];
  lanza = refWith [{ loom.boot.secureBoot.enable = lib.mkForce true; loom.boot.loader = "lanzaboote"; }];

  # ---- hw-quirks ----------------------------------------------------------
  table = builtins.fromTOML (builtins.readFile ../fork/hw-quirks.toml);
  camel = s: let w = lib.splitString "-" s; in lib.head w
    + lib.concatMapStrings (x: lib.toUpper (lib.substring 0 1 x) + lib.substring 1 (-1) x) (lib.tail w);
  v1 = lib.filterAttrs (_: q: q.status == "v1") table.quirk;
  needsNixosHardware = lib.filterAttrs (_: q: q ? nixos-hardware) v1;
  together = builtins.attrNames (removeAttrs v1 (builtins.attrNames needsNixosHardware));

  on = names: { omanix.hardware.quirks = lib.genAttrs (map camel names) (_: { enable = true; }); };
  # Every quirk that doesn't bring a nixos-hardware kernel, on at once …
  allQuirks = refWith [ ../hosts/fixtures/unfree.nix (on together) ];
  # … and each nixos-hardware one on its own, with its module imported.
  alone = lib.mapAttrs (n: q: refWith [ nh.${q.nixos-hardware} (on [ n ]) ]) needsNixosHardware;
  # Without the nixos-hardware module, the quirk says what to import.
  surfaceWithoutNh = refWith [ (on [ "surface" ]) ];

  hostFor = n: alone.${n} or allQuirks;
  cfgOf = n: (hostFor n).config // { _options = (hostFor n).options; };
  hm = h: h.home-manager.users.${h.loom.user.name};
  has = needle: hay: lib.hasInfix needle hay;
  names = ps: map lib.getName ps;

  # What each quirk's mechanism must put into the system (row name → check).
  expect = {
    nouveau-cursor = h: has "no_hardware_cursors = true" (hm h).xdg.configFile."hypr/looknfeel.lua".text;
    vm-no-animations = h: h.systemd.user.services ? omanix-quirk-vm-no-animations;
    intel-video = h: builtins.elem "intel-media-driver" (names h.hardware.graphics.extraPackages);
    intel-thermald = h: h.services.thermald.enable;
    # hardware.firmware applies into one firmware env: look at its definitions
    intel-sof = h: builtins.elem "sof-firmware" (names (lib.concatLists h._options.hardware.firmware.definitions));
    intel-ptl-fred = h: builtins.elem "fred=on" h.boot.kernelParams;
    intel-wifi7-eht = h: has "iwlwifi disable_11be=Y" h.boot.extraModprobeConfig;
    intel-ipu7-camera = h: h.hardware.ipu7.enable;
    asus-rog = h: h.services.asusd.enable && h.systemd.services ? omanix-asus-alc285;
    asus-z13-touchpad = h: has "1a30" h.services.udev.extraRules;
    asus-b9406-display = h: builtins.elem "xe.enable_panel_replay=0" h.boot.kernelParams;
    asus-b9406-touchpad = h: has "B9406" h.environment.etc."libinput/local-overrides.quirks".text;
    asus-ptl-backlight = h: builtins.elem "xe.enable_dpcd_backlight=1" h.boot.kernelParams;
    framework16 = h: builtins.elem "qmk_hid" (names h.environment.systemPackages) && has "32ac" h.services.udev.extraRules;
    framework13-amd-mic = h: h.services.pipewire.wireplumber.extraConfig ? "90-omanix-framework13-mic";
    lenovo-yoga-pro7-bass = h: has "alc287-yoga9-bass-spk-pin" h.boot.extraModprobeConfig;
    surface = h: builtins.elem "surface_kbd" h.boot.initrd.kernelModules;
    apple-t2 = h: builtins.elem "mem_sleep_default=deep" h.boot.kernelParams;
    apple-brcmfmac = h: has "brcmfmac feature_disable=0x82000" h.boot.extraModprobeConfig;
    apple-spi-keyboard = h: builtins.elem "applespi" h.boot.initrd.kernelModules;
    apple-nvme-suspend = h: h.systemd.services ? omanix-apple-nvme-suspend;
    bcm43xx = h: builtins.elem "wl" h.boot.kernelModules;
    tuxedo-backlight = h: h.hardware.tuxedo-drivers.enable;
    synaptics-intertouch = h: has "synaptics_intertouch=1" h.boot.extraModprobeConfig;
    elgato-camlink-4k = h: h.services.v4l2-relayd.instances.camlink.enable;
    speaker-tuning = h: h.systemd.user.services ? omanix-speaker-tuning;
    nvidia = h: builtins.elem "nvidia" h.services.xserver.videoDrivers && h.hardware.nvidia.open;
    hybrid-gpu = h: h.services.supergfxd.enable;
  };

  # U26: what v1 rows rely on exists; what deferred rows wait for doesn't yet.
  exists = h: ref:
    if lib.hasPrefix "pkgs." ref then (builtins.tryEval (lib.hasAttrByPath (lib.splitString "." (lib.removePrefix "pkgs." ref)) pkgs)).value
    else lib.hasAttrByPath (lib.splitString "." (lib.removePrefix "option:" ref)) h.options;

  quirkErrors =
    lib.concatMap (h: map (m: "quirks on together/alone: ${m}") (failedAssertions h)) ([ allQuirks ] ++ builtins.attrValues alone)
    ++ lib.optional (drv allQuirks == "") "no toplevel with every quirk on"
    ++ lib.concatLists (lib.mapAttrsToList (n: _:
      if !(expect ? ${n}) then [ "quirk ${n}: no expectation in checks/hardware.nix" ]
      else lib.optional (!(expect.${n} (cfgOf n))) "quirk ${n}: its mechanism is missing from the evaluated system") v1)
    ++ lib.concatLists (lib.mapAttrsToList (n: q: map (r: "quirk ${n}: requires ${r}, which this nixpkgs lacks (U26)")
      (lib.filter (r: !(exists (hostFor n) r)) (q.requires or [ ]))) v1)
    ++ lib.concatLists (lib.mapAttrsToList (n: q: map (r: "quirk ${n}: ${r} now exists (U26); package the quirk and make it v1")
      (lib.filter (r: exists allQuirks r) (q.missing or [ ]))) table.quirk)
    ++ lib.optional (!(lib.any (lib.hasInfix "nixos-hardware") (failedAssertions surfaceWithoutNh)))
      "quirk surface without nixos-hardware's module: no assertion naming it"
    # U27: omarchy's NvPCR drop-ins stay out of the system (not adopted).
    ++ map (n: "U27: ${n} is installed; the NvPCR drop-ins are DROP pending U27")
      (lib.filter (lib.hasInfix "pcr") (builtins.attrNames hosts.ref-default.config.environment.etc));
in
{
  # §i.1 omanix flavor (eval-ref-default is W15's, in desktop.nix).
  eval-ref-nvidia = c.mkCheck pkgs "eval-ref-nvidia" (evaluates hosts.ref-nvidia
    ++ lib.optional (!hosts.ref-nvidia.config.hardware.nvidia.open) "the GSP GPU doesn't get the open modules");
  eval-ref-laptop = c.mkCheck pkgs "eval-ref-laptop" (evaluates hosts.ref-laptop
    ++ lib.optional (hosts.ref-laptop.config.services.xserver.xkb.layout != "us,de") "omanix.input.layouts doesn't reach the XKB layout"
    ++ lib.optional (!hosts.ref-laptop.config.omanix.hardware.laptop) "hardware.json's battery doesn't make it a laptop");
  eval-vm-test = c.mkCheck pkgs "eval-vm-test" (evaluates hosts.vm-test
    ++ lib.optional (!hosts.vm-test.config.omanix.hardware.isVM) "hardware.json's virt doesn't make it a VM");
  eval-omanix-no-agent = c.mkCheck pkgs "eval-omanix-no-agent" (evaluates noAgent
    ++ lib.optional (noAgent.config.users.users ? ada) "the resident exists with loom.agent.enable = false");
  eval-omanix-agent-sudo-approval = c.mkCheck pkgs "eval-omanix-agent-sudo-approval" (evaluates agentAny
    ++ lib.optional (agentAny.config.nuketown.agents.ada.sudo.approvalAllow != null) "sudo = \"any\" must give approvalAllow = null");
  eval-omanix-reviewer-off = c.mkCheck pkgs "eval-omanix-reviewer-off" (evaluates reviewerOff
    ++ lib.optional (reviewerOff.config.users.users ? reviewer) "the reviewer exists with loom.reviewer.enable = false");
  eval-omanix-lanzaboote = c.mkCheck pkgs "eval-omanix-lanzaboote" (evaluates lanza
    ++ lib.optional (!lanza.config.boot.lanzaboote.enable) "lanzaboote is off");

  # §f.2.6: coverage of upstream's hardware scripts, a module per v1 row that
  # evaluates and does what its row says, U26 and U27, and (through the
  # package build) the probe pytest with a sysfs fixture per probe.
  hw-quirks = pkgs.runCommand "omanix-check-hw-quirks"
    {
      nativeBuildInputs = [ python3 ];
      passAsFile = [ "errors" ];
      errors = lib.concatStringsSep "\n" quirkErrors;
      probe = pkgs.omanix-hw-probe;   # its pytest runs in its build
    }
    ''
      python3 -I ${../fork/tools/hwquirks.py} ${pkgs.omanixFork.src} ${../fork/hw-quirks.toml} ${../modules/omanix/hardware/quirks}
      if [ -s "$errorsPath" ]; then cat "$errorsPath" >&2; exit 1; fi
      test -x "$probe/bin/omanix-hw-probe"
      touch $out
    '';

  # §i.2 writers-respect-hm, W17's cases: font set and text size, input
  # (U28), defaults and apps (U35). W16 adds the glass and chromium-wrapper
  # cases to the same test.
  writers-respect-hm = import ../tests/writers-respect-hm.nix { inherit pkgs loom; omanix = self; };

  # The nouveau-cursor fixture: the built HM looknfeel.lua carries the setting.
  quirk-nouveau-cursor =
    let h = refWith [ (on [ "nouveau-cursor" ]) ]; in
    pkgs.runCommand "omanix-check-quirk-nouveau-cursor" { } ''
      f=${(hm h.config).home-files}/.config/hypr/looknfeel.lua
      cat "$f"
      grep -q 'no_hardware_cursors = true' "$f"
      touch $out
    '';
}
