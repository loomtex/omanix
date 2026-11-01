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
  # ever publishes that) and as allocated on disk. docs: what stays of
  # /share/doc outputs that a program references at runtime (git, mpv), see
  # hosts/budget.nix.
  #
  # Measured 2026-10-31 (nixos-unstable 31ecbac, linux-firmware 20261019):
  #   offline 5.41 GiB raw (4.22 GiB .zst): ESP 512 MiB + STORE + CACHE
  #     2.68 GiB + CFG 256 MiB. The live store keeps the whole firmware set,
  #     shared with the reference closures in CACHE, so the live-system cuts
  #     mostly move paths into CACHE (5.49 → 5.41 GiB). Budget 6 GiB, Josh's
  #     bar (omarchy's ISO is ~6 GB): ~10% headroom.
  #   net 1.74 GiB raw (0.73 GiB .zst): ESP + CFG are 768 MiB of it, the
  #     STORE ~1 GiB (closure 1.36 GiB NAR, firmware 224 MiB of that, from
  #     loom.lib.installerFirmware.net). Was 2.48 GiB raw before the
  #     per-driver firmware and the doc/ModemManager/systemd cuts. Budget
  #     2 GiB: ~15% headroom.
  budget = {
    offlineImage = 6 * 1024 * 1024 * 1024;     # 6 GiB
    netImage = 2 * 1024 * 1024 * 1024;         # 2 GiB
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

  # §e.1: the offline image (CACHE included) ≤ 6 GiB, the net image
  # ≤ 2 GiB, the doc outputs of the reference closures capped. Prints the
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
} // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  # §i.2: configure → flash → offline install → first boot, cacheMiss = [].
  installer-e2e-omanix = import ../tests/installer-e2e-omanix.nix { inherit pkgs self inputs; };
}
