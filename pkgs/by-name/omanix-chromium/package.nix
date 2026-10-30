# omanix-chromium: Chromium that reads ~/.config/chromium-flags.conf and its
# runtime overlay (§f.4.2, §f.5), like Arch's launcher does. nixpkgs'
# chromium does not read that file; the wrapper passes what
# omanix-chromium-flags prints, then the command line. The default of
# omanix.apps.chromium.package; any other Chromium is wrapped with
# `omanix-chromium.override { chromium = …; }`.
{
  lib,
  symlinkJoin,
  writeShellScript,
  chromium,
  omanix-chromium-flags,
}:

let
  launch = bin: writeShellScript "chromium-omanix-${bin}" ''
    # omanix: Chromium with ~/.config/chromium-flags.conf and its overlay.
    mapfile -d "" -t flags < <(${lib.getExe omanix-chromium-flags} -0)
    exec ${chromium}/bin/${bin} "''${flags[@]}" "$@"
  '';
in
symlinkJoin {
  name = "chromium-omanix-${chromium.version or "unknown"}";
  paths = [ chromium ];
  postBuild = ''
    for b in chromium chromium-browser; do
      [ -e $out/bin/$b ] || continue
      rm $out/bin/$b
    done
    ln -s ${launch "chromium"} $out/bin/chromium
    [ -e ${chromium}/bin/chromium-browser ] && ln -s ${launch "chromium-browser"} $out/bin/chromium-browser || true
  '';
  passthru = { unwrapped = chromium; };
  meta = (chromium.meta or { }) // { mainProgram = "chromium"; };
}
