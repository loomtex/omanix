{
  description = "omanix plugin fixture (checks.plugin-fixture)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    # A service with a DynamicUser StateDirectory: the persist audit must ask
    # for /var/lib/private/omanix-fixture (U32).
    nixosModules.default = { pkgs, ... }: {
      systemd.services.omanix-fixture = {
        description = "omanix plugin fixture";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          DynamicUser = true;
          StateDirectory = "omanix-fixture";
          ExecStart = "${pkgs.coreutils}/bin/touch /var/lib/omanix-fixture/sentinel";
        };
      };
    };
    # A home-manager module (U30).
    homeModules.default = { ... }: {
      home.file.".omanix-fixture".text = "from the plugin fixture\n";
    };
  };
}
