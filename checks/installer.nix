# W20's checks: the installer images, their size, the scripts and the
# copies of the host template (§e.1, §e.10, §i.1). The VM test
# installer-e2e-omanix is in tests/installer-e2e-omanix.nix.
{ pkgs, self, inputs }:

let
  inherit (pkgs) lib;
  py = pkgs.python3;
  installer = self.lib.installer;
  refNames = [ "ref-default" "ref-nvidia" "ref-laptop" ];
  refs = map (n: self.nixosConfigurations.${n}) refNames;
  offline = installer.system { };
  net = installer.system { variant = "net"; };

  # §e.1 closure budgets. Image sizes are the .raw files a release ships
  # (omanix-release copies the .raw into the release; flash-usb writes it);
  # the check also prints each as .raw.zst (a smaller download, if a release
  # ever publishes that), as allocated on disk, and its partitions. docs:
  # what stays of /share/doc outputs that a program references at runtime
  # (git, mpv), see hosts/budget.nix.
  #
  # Measured 2026-11-01 (nixos-unstable 31ecbac, linux-firmware 20261019).
  # No OMANIX-CFG in the image (the first boot or loom-flash makes it), the
  # ESP sized to its files (repart's 100 MiB ESP minimum: the UKI is 42 MB),
  # STORE and CACHE erofs zstd 15 with 1 MiB pclusters and tail packing:
  #   offline 4.39 GiB raw (4.26 GiB .zst): ESP 100 MiB + STORE 1.60 GiB +
  #     CACHE 2.70 GiB. Was 5.41 GiB (ESP 512 MiB, STORE 1.98 GiB, CACHE
  #     2.68 GiB, CFG 256 MiB). The live store shares every per-driver
  #     firmware package with CACHE's reference closures. CACHE is .nar.zst:
  #     zstd 15 saves 1.4 MB there. Budget 5 GiB: ~14% headroom.
  #   net 0.83 GiB raw (0.71 GiB .zst): ESP 100 MiB + STORE 748 MiB (closure
  #     1.36 GiB NAR). Was 1.74 GiB (ESP 512 MiB, STORE 1015 MiB, CFG
  #     256 MiB). Budget 1 GiB: ~20% headroom.
  budget = {
    offlineImage = 5 * 1024 * 1024 * 1024;     # 5 GiB
    netImage = 1024 * 1024 * 1024;             # 1 GiB
    docOutputs = 32 * 1024 * 1024;             # 32 MiB over the reference closures
  };

  closureOf = name: drvs: pkgs.closureInfo { rootPaths = drvs; } // { inherit name; };
  closures = {
    references = closureOf "references" (map (r: r.config.system.build.toplevel) refs);
    installer-offline = closureOf "installer-offline" [ offline.config.system.build.toplevel ];
    installer-net = closureOf "installer-net" [ net.config.system.build.toplevel ];
  };
in
{
  # §e.10: every scripts/*.sh carries the same preamble, byte for byte, and
  # starts with it; nothing runs before the verification; shellcheck clean.
  script-preamble-identical = pkgs.runCommand "omanix-check-script-preamble-identical"
    { nativeBuildInputs = [ py pkgs.shellcheck ]; } ''
    python3 -I ${./installer/preamble.py} ${../scripts}
    shellcheck -x ${../scripts}/*.sh
    touch $out
  '';

  # hosts/reference and tests/fixtures/host-vm-omanix are templates/host plus
  # placeholder sops files (and, for the test variant, modules/test-vm.nix);
  # nothing else may drift.
  reference-templates = pkgs.runCommand "omanix-check-reference-templates" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
    norm() { cp -r "$1" "$2" && chmod -R u+w "$2" && rm -f "$2"/secrets/.gitkeep "$2"/secrets/user.yaml "$2"/secrets/agents.yaml; }
    norm ${../templates/host} t
    norm ${../hosts/reference} r
    diff -r t r
    norm ${../tests/fixtures/host-vm-omanix} v
    rm v/modules/test-vm.nix
    sed -i 's| ./test-vm.nix ]| ]|' v/modules/default.nix
    diff -r t v
    for d in ${../hosts/reference} ${../tests/fixtures/host-vm-omanix}; do
      grep -q '^sops:' $d/secrets/user.yaml && grep -q '^sops:' $d/secrets/agents.yaml
    done
    touch $out
  '';

  # omanix.catalog.hostgen (what the installer and configure validate
  # against) equals the built catalog's hostgen.json.
  hostgen-catalog = pkgs.runCommand "omanix-check-hostgen-catalog" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -S . ${builtins.toFile "hostgen.json" (builtins.toJSON (lib.head refs).config.omanix.catalog.hostgen)} > want
    jq -S . ${(lib.head refs).config.omanix.catalog.package}/share/omanix/catalog/hostgen.json > got
    diff want got
    touch $out
  '';

  # §e.1: no second Mesa, LLVM or Python (major.minor) in the reference
  # closures or in either installer.
  closure-dupes = pkgs.runCommand "omanix-check-closure-dupes" { nativeBuildInputs = [ py ]; } ''
    python3 -I ${./installer/closure.py} dupes \
      ${lib.concatMapStringsSep " " (c: "${c.name}=${c}/store-paths") (lib.attrValues closures)}
    touch $out
  '';

  # §e.1: the offline image (CACHE included) ≤ 5 GiB, the net image
  # ≤ 1 GiB, the doc outputs of the reference closures capped. Prints the
  # numbers either way (they are the report to Josh when a budget breaks).
  closure-budget = pkgs.runCommand "omanix-check-closure-budget" { nativeBuildInputs = [ py pkgs.zstd ]; } ''
    python3 -I ${./installer/closure.py} budget \
      --budget ${builtins.toFile "budget.json" (builtins.toJSON budget)} \
      --image offline=${offline.config.system.build.image} \
      --image net=${net.config.system.build.image} \
      --cache ${offline.config.system.build.omanixStickCache}/omanix-cache.json \
      --docs ${closures.references}/store-paths \
      ${lib.concatMapStringsSep " " (c: "--closure ${c.name}=${c}/store-paths") (lib.attrValues closures)} \
      --out $out
  '';

  # A host installed on real hardware (hardware.json with real modules and
  # their modinfo firmware names): its firmware is only the per-driver
  # packages those ask for, and every one of them is on the offline stick
  # (live store + CACHE), so an offline install builds nothing but the
  # per-host firmware env. Before per-driver host firmware, that set was a
  # runCommand over the uncompressed pkgs.linux-firmware (~1 GB), which no
  # stick carried.
  host-firmware-offline =
    let
      hw = lib.importJSON "${inputs.loom}/tests/fixtures/hardware/laptop-amd-intel.json";
      host = (lib.head refs).extendModules { modules = [{ loom.hardware.facts = lib.mkForce hw; }]; };
      env = host.config.hardware.firmware;
      need = pkgs.closureInfo { rootPaths = [ env ]; };
      want = [ "amdgpu" "btusb" "isp" "iwlwifi" "r8169" ];
    in
    pkgs.runCommand "omanix-check-host-firmware-offline" { } ''
      grep -vx '${env}' ${need}/store-paths | sort > need
      sort ${offline.config.system.build.omanixStickIndex}/store-paths > have
      echo "the host's firmware paths:"; sed 's|^/nix/store/[a-z0-9]*-|  |' need
      missing=$(comm -23 need have)
      if [ -n "$missing" ]; then
        echo "FAIL: not on the offline stick:" >&2; echo "$missing" >&2; exit 1
      fi
      got=$(sed -n 's|^/nix/store/[a-z0-9]*-linux-firmware-\(.*\)-${pkgs.linux-firmware.version}-zstd$|\1|p' need | sort | tr '\n' ' ')
      if [ "$got" != "${lib.concatStringsSep " " want} " ]; then
        echo "FAIL: linux-firmware drivers: got [$got], want [${toString want}]" >&2; exit 1
      fi
      if grep -E -- '-linux-firmware-${pkgs.linux-firmware.version}(-zstd)?$' need; then
        echo "FAIL: the whole linux-firmware is in the host's closure" >&2; exit 1
      fi
      echo "PASS: host-firmware-offline ($got)"
      touch $out
    '';
} // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  # §i.2: configure → flash → offline install → first boot, cacheMiss = [].
  installer-e2e-omanix = import ../tests/installer-e2e-omanix.nix { inherit pkgs self inputs; };

  # The net image written with dd to a bigger disk: the first boot makes
  # OMANIX-CFG, the second reuses it, no room → a warning (loom's script).
  installer-image-cfg = import "${inputs.loom}/tests/lib/image-cfg.nix" {
    inherit pkgs;
    name = "omanix-installer-image-cfg";
    specialArgs = { inputs = { }; inherit (inputs) loom; };
    modules = installer.modules { variant = "net"; test = true; image = true; };
    memorySize = 3072;
  };
}
