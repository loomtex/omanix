# omanix-release: build, sign and verify releases (§e.1, §e.10, D11), and the
# stick cache builder lib/installer.nix runs. Python stdlib; the pytest suite
# (throwaway keys made in the build) runs in checkPhase. It holds no key.
{ lib, stdenvNoCC, python3, makeWrapper, openssh, git, nix, coreutils }:

stdenvNoCC.mkDerivation {
  pname = "omanix-release";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./omanix_release.py ./stick_cache.py ./tests ];
  };
  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ (python3.withPackages (p: [ p.pytest ])) openssh git nix coreutils ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export HOME=$TMPDIR NIX_STATE_DIR=$TMPDIR/nix NIX_CONF_DIR=$TMPDIR
    PYTHONPATH=$PWD python3 -m pytest -q -p no:cacheprovider tests
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0644 omanix_release.py $out/lib/omanix-release/omanix_release.py
    install -Dm0644 stick_cache.py $out/lib/omanix-release/stick_cache.py
    makeWrapper ${python3}/bin/python3 $out/bin/omanix-release \
      --add-flags "-sE $out/lib/omanix-release/omanix_release.py" \
      --prefix PATH : ${lib.makeBinPath [ openssh git coreutils ]} --suffix PATH : ${lib.makeBinPath [ nix ]}
    runHook postInstall
  '';
  meta = {
    description = "omanix release tooling: sign and verify SHA256SUMS, sign the stick cache, build a release from a signed tag";
    mainProgram = "omanix-release";
    license = lib.licenses.mit;
  };
}
