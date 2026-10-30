{
  description = "example — a omanix host";

  inputs = {
    omanix.url = "git+https://silo.loom.farm/omanix.git?ref=refs/tags/v0.1.0";
    nixpkgs.follows = "omanix/nixpkgs"; # one nixpkgs / one HM for plugins (one Mesa, one Qt)
    home-manager.follows = "omanix/home-manager";
    # plugins are added here by `omanix plugin add`; each one appears on an approval card
  };

  outputs =
    inputs@{ self, omanix, ... }:
    {
      nixosConfigurations.host = omanix.lib.mkHost { inherit self inputs; };
      checks.x86_64-linux.host = self.nixosConfigurations.host.config.system.build.toplevel;
    };
}
