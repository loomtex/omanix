# omanix-chromium-flags: what the omanix chromium wrapper (omanix-chromium)
# reads from ~/.config/chromium-flags.conf and its overlay.
# nixpkgs' chromium does not read that file by itself (§f.5).
{ writeShellApplication, gnused }:

writeShellApplication {
  name = "omanix-chromium-flags";
  runtimeInputs = [ gnused ];
  text = builtins.readFile ./omanix-chromium-flags.sh;
}
