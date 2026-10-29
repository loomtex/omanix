# omanix.hardware: facts from loom-detect (hardware.json) and the quirk
# modules (§f.2.6). Each quirks/<name>.nix declares
# omanix.hardware.quirks.<name>.enable; loom-hostgen enables the ones whose
# probe (fork/hw-quirks.toml, probes.nix) matched at install. The generic
# per-vendor defaults are bluetooth.nix and wireless.nix; Vulkan needs
# nothing (Mesa, NixOS's default, carries RADV and ANV).
{ config, lib, ... }:

let
  cfg = config.omanix;
  facts = config.loom.hardware.facts;
  quirkFiles = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (builtins.readDir ./quirks);

  vendorOf = g: if builtins.isAttrs g then g.vendor or "other" else g;
  gpuVendors = lib.unique (map vendorOf (facts.gpu or [ ]));
in
{
  imports = [ ./bluetooth.nix ./wireless.nix ./probes.nix ]
    ++ map (n: ./quirks + "/${n}") (builtins.attrNames quirkFiles);

  options.omanix.hardware = {
    gpu = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "intel" "amd" "nvidia" "other" ]);
      default = map (v: if builtins.elem v [ "intel" "amd" "nvidia" ] then v else "other") gpuVendors;
      defaultText = lib.literalExpression "GPU vendors from loom.hardware.facts.gpu";
      example = [ "intel" "nvidia" ];
      description = "The machine's GPU vendors (from hardware.json).";
    };
    isVM = lib.mkOption {
      type = lib.types.bool;
      default = (facts.virt or "none") != "none";
      defaultText = lib.literalExpression "loom.hardware.facts.virt != \"none\"";
      description = "Whether this is a virtual machine (from hardware.json).";
    };
    laptop = lib.mkOption {
      type = lib.types.bool;
      default = facts.battery or false;
      defaultText = lib.literalExpression "loom.hardware.facts.battery";
      description = "Whether the machine runs on a battery (from hardware.json).";
    };
  };

  config = lib.mkIf cfg.enable {
    # install/hardware/fix-fkeys.sh: F-keys on Apple-layout keyboards (Lofree
    # Flow and the like) are F-keys.
    boot.extraModprobeConfig = ''
      options hid_apple fnmode=2
    '';
  };
}
