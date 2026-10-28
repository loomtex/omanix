# omarchy at the fork point, with fork/ applied (§f.2.4). Every stage runs in
# the sandbox and only reads, copies, patches and rewrites upstream files.
{
  lib,
  runCommand,
  python3,
  bash,
  patch,
  omanixFork,
  # false skips stage 6, for regenerating fork/residual.toml
  postCheck ? true,
}:

let
  f = omanixFork.forkDir;
in
runCommand "omarchy-src-${omanixFork.version}"
  {
    nativeBuildInputs = [ python3 patch ];
    # interpreters patchShebangs resolves against
    buildInputs = [ bash python3 ];
    passthru = { inherit (omanixFork) upstream; };
    meta = {
      description = "omarchy ${omanixFork.upstream.tag} with the omanix fork applied";
      homepage = "https://github.com/omacom/omarchy";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    cp -r --no-preserve=ownership ${omanixFork.src} $out
    chmod -R u+w $out
    py() { python3 -I ${f}/tools/assemble.py "$@"; }

    # 2. drop  3. add
    py drop $out ${f}/drop.txt
    py add $out ${f}/add ${omanixFork.src}

    # 4. patch, in order, exact
    for p in ${f}/patches/*.patch; do
      [ -e "$p" ] || continue
      echo "patch: $(basename "$p")"
      patch -d $out -p1 --fuzz=0 --no-backup-if-mismatch --forward < "$p"
    done

    # 5. rewrite (exact counts), then shebangs
    py rewrite $out ${f}/rewrite.toml
    patchShebangs --host $out/bin $out/default $out/shell $out/config $out/etc $out/themes $out/applications >/dev/null

    # 6. post-check
    ${lib.optionalString postCheck ''
      python3 -I ${f}/tools/forkcheck.py post $out ${f}/classify.toml ${f}/residual.toml ${f}/add
      python3 -I ${f}/tools/forkcheck.py license ${omanixFork.src} $out ${f}/UPSTREAM.toml
    ''}
  ''
