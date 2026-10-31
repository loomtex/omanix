# W17's cases (defaults, apps, fonts, input) need these declared on the node:
# non-upstream defaults (so the test sees them applied), a declared app with
# an autostart, a chromium feature, a web app with a binding and a font-set
# hook. The heavy apps add nothing to the cases.
{ pkgs, ... }:

let
  autostartProbe = pkgs.writeShellScriptBin "omanix-autostart-probe" ''
    touch "$XDG_RUNTIME_DIR/omanix-autostart-ok"
  '';
in
{
  omanix.defaults = { terminal = "alacritty"; browser = "chromium"; editor = "nvim"; };
  omanix.apps.autostart-probe = { packages = [ autostartProbe ]; autostart = "omanix-autostart-probe"; };
  omanix.apps.chromium.features = [ "WebUIDarkMode" ];
  omanix.apps.webapps.Linear = { url = "https://linear.app"; icon = "linear"; bind = "SUPER + CTRL + ALT + L"; };
  omanix.hooks.font-set = ''echo "$1" > "$HOME/.cache/omanix-hook-font-set"'';
  omanix.apps.libreoffice.enable = false;
  omanix.apps.docker.enable = false;
}
