# omanix-configure: `nix run .#configure` (§e.2): loom-mint/loom-enroll with
# the omanix template and catalog, `check` (cacheMiss, drvgraph.py) and
# `stage-cache`. Python stdlib; pytest runs in the build. Built by
# lib/tools.nix, which passes the settings (template, hostgen catalog, the
# host flake.lock pinning omanix to this source, the check module, silo).
{ lib, stdenvNoCC, python3, makeWrapper, writeText, nix, git, openssh, coreutils
, loom-mint, loom-enroll, settings }:

stdenvNoCC.mkDerivation {
  pname = "omanix-configure";
  version = "0.1.0";
  src = lib.fileset.toSource { root = ./.; fileset = lib.fileset.unions [ ./omanix_configure.py ./drvgraph.py ./tests ]; };
  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ (python3.withPackages (p: [ p.pytest ])) ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PYTHONPATH=$PWD python3 -m pytest -q -p no:cacheprovider tests
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0644 -t $out/lib/omanix-configure omanix_configure.py drvgraph.py
    install -Dm0644 ${writeText "configure-settings.json" (builtins.toJSON (settings // {
      loomMintLib = "${loom-mint}/lib/loom-mint";
    }))} $out/share/omanix-configure/settings.json
    makeWrapper ${python3}/bin/python3 $out/bin/omanix-configure \
      --add-flags "-sE $out/lib/omanix-configure/omanix_configure.py" \
      --set OMANIX_CONFIGURE_SETTINGS $out/share/omanix-configure/settings.json \
      --prefix PATH : ${lib.makeBinPath [ loom-mint loom-enroll git openssh coreutils ]} \
      --suffix PATH : ${lib.makeBinPath [ nix ]}
    runHook postInstall
  '';
  meta = { description = "omanix configure engine (§e.2)"; mainProgram = "omanix-configure"; license = lib.licenses.mit; };
}
