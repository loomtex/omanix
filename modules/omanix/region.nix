# omanix.region: package mirrors only, never new trust. "cn" puts the
# Chinese mirrors of cache.nixos.org first; they serve the same store paths
# signed by the same key, so nix.settings.trusted-public-keys is unchanged
# (upstream's region step chose pacman mirrors; that part is DROP).
{ config, lib, ... }:

let
  cfg = config.omanix;
  mirrors = {
    global = [ ];
    cn = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://mirrors.ustc.edu.cn/nix-channels/store"
    ];
  };
in
{
  options.omanix.region = lib.mkOption {
    type = lib.types.enum (builtins.attrNames mirrors);
    default = "global";
    example = "cn";
    description = "Where packages are downloaded from (mirrors of cache.nixos.org; the signing key stays the same).";
  };

  config = lib.mkIf (cfg.enable && mirrors.${cfg.region} != [ ]) {
    nix.settings.substituters = lib.mkBefore mirrors.${cfg.region};
  };
}
