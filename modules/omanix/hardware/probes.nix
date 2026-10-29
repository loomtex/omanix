# The omanix hardware probes for the installer (loom.installer.probes, §e.5):
# one entry per v1 quirk in fork/hw-quirks.toml. Each command is
# `omanix-hw-probe --check <quirk>` (exit 0 = present), which evaluates the
# row's declarative probe against /sys, /proc and `lspci -nn`; it never runs
# omarchy code. Probes are named by the quirk's option (camelCase: the row
# asus-rog is omanix.hardware.quirks.asusRog), so a match becomes
# `omanix.hardware.quirks.<probe>.enable = true;` in the host's hardware.nix
# (loom-hostgen).
{ config, lib, pkgs, ... }:

let
  quirks = (builtins.fromTOML (builtins.readFile ../../../fork/hw-quirks.toml)).quirk;
  v1 = lib.filterAttrs (_: q: q.status == "v1") quirks;
  camel = s: let w = lib.splitString "-" s; in lib.head w
    + lib.concatMapStrings (x: lib.toUpper (lib.substring 0 1 x) + lib.substring 1 (-1) x) (lib.tail w);
  probe = name: (pkgs.writeShellScriptBin "omanix-probe-${name}" ''
    exec ${pkgs.omanix-hw-probe}/bin/omanix-hw-probe --check ${lib.escapeShellArg name}
  '').overrideAttrs { meta.mainProgram = "omanix-probe-${name}"; };
in
{
  config = lib.mkIf config.omanix.enable {
    loom.installer.probes = lib.mapAttrs' (name: _: lib.nameValuePair (camel name) { command = probe name; emits = "quirk"; }) v1;
  };
}
