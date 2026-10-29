# Fixture-only: the unfree packages the hardware fixtures need, on top of the
# harness loom allows (loom sets the predicate with mkDefault).
{ lib, ... }:

{
  nixpkgs.config.allowUnfreePredicate = p: builtins.elem (lib.getName p) [
    "claude-code" "nvidia-x11" "nvidia-settings" "nvidia-persistenced" "broadcom-sta" "obsidian" "ipu7-camera-bins" "ivsc-firmware" "ivsc-firmware-unstable"
  ];
  # bcm43xx: nixpkgs marks broadcom-sta insecure (unmaintained driver).
  nixpkgs.config.allowInsecurePredicate = p: lib.getName p == "broadcom-sta";
}
