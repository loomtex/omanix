# omanix.hooks.<name>: declared hooks (post-boot, theme-set, font-set, …).
# ~/.config/omarchy/hooks/ is user data and never HM-owned, so declared
# hooks go to /etc/omanix/hooks/<name>; omarchy-hook runs them before the
# user's own (that part of omarchy-hook is a fork patch, see W15 notes).
{ config, lib, ... }:

let
  cfg = config.omanix;
in
{
  options.omanix.hooks = lib.mkOption {
    type = lib.types.attrsOf lib.types.lines;
    default = { };
    example = { post-boot = "notify-send 'Welcome back'"; };
    description = ''
      Bash run by `omarchy-hook <name>` in the human's session, before the
      hooks in `~/.config/omarchy/hooks/`. Names are upstream's fixed labels.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: _: {
      assertion = builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*" name != null;
      message = "omanix.hooks: '${name}' is not a hook name (letters, digits, '.', '_', '-').";
    }) cfg.hooks;

    environment.etc = lib.mkIf (cfg.hooks != { }) (lib.mapAttrs' (name: text: lib.nameValuePair "omanix/hooks/${name}" {
      text = "# omanix.hooks.${name} (host configuration)\n" + text;
      mode = "0644";
    }) cfg.hooks);
  };
}
