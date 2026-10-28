# Hyprland as omarchy ships it: nixpkgs' 0.56.2 plus omarchy-pkgs' four
# patches (§f.2.9). Building from nixpkgs keeps Mesa/Qt/wayland on one
# nixpkgs, which the Hyprland flake would not.
{ lib, hyprland }:

assert lib.assertMsg (hyprland.version == "0.56.2")
  "hyprland-omarchy: the vendored patches are for 0.56.2, nixpkgs has ${hyprland.version}; rebase them (porting report)";

hyprland.overrideAttrs (old: {
  pname = "hyprland-omarchy";
  patches = (old.patches or [ ]) ++ [
    ./patches/software-renderer.patch
    ./patches/nvidia-egl-teardown.patch
    ./patches/wl-output-global-grace.patch
    ./patches/monitor-rule-vrr.patch
  ];
  patchFlags = [ "-p1" "--fuzz=0" ];
  passthru = old.passthru // { omarchyPatches = 4; };
})
