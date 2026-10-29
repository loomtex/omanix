# Option paths omanix's own modules may set above mkDefault, each with a
# reason (checks.priorities; loom's list applies too, see lib/default.nix).
# A path matches the option itself and everything below it.
[
  {
    option = "services.displayManager.sessionPackages";
    reason = "a list that only appends: the omarchy uwsm session next to whatever the host adds";
  }
  {
    option = "systemd.packages";
    reason = "a list that only appends: upstream's user units, enabled below by name";
  }
  {
    option = "systemd.user.services.";
    reason = "enables upstream's first-run user units by name (wantedBy is a list merge) and defines omanix's own session units";
  }
  {
    option = "systemd.user.paths.omanix-";
    reason = "omanix's own path unit";
  }
  {
    option = "systemd.tmpfiles.rules";
    reason = "a list that only appends: /run/omanix/session";
  }
  {
    option = "system.systemBuilderCommands";
    reason = "lines that only append: the $out/omarchy link (§f.2.9); not a preference";
  }
  {
    option = "system.extraSystemBuilderCmds";
    reason = "alias of systemBuilderCommands";
  }
  {
    option = "environment.sessionVariables.OMARCHY_";
    reason = "OMARCHY_PATH and OMARCHY_LANGUAGE_FILE must point at this generation's tree; a host never moves them";
  }
  {
    option = "environment.sessionVariables.OMANIX_";
    reason = "omanix's own variables";
  }
  {
    option = "environment.extraInit";
    reason = "lines that only append: env-bootstrap (P15)";
  }
  {
    option = "environment.extraSetup";
    reason = "lines that only append: the package manifests and catalog in system-path (P6)";
  }
  {
    option = "environment.etc.\"omanix/";
    reason = "omanix's own files under /etc/omanix (version, titlebars .so, settle.json, hooks)";
  }
  {
    option = "environment.etc.\"xdg/uwsm/env\"";
    reason = "the uwsm env file that loads env-bootstrap; generated, not a preference";
  }
  {
    option = "xdg.portal.extraPortals";
    reason = "a list that only appends: the GTK portal next to Hyprland's";
  }
  {
    option = "users.groups.omanix-resident";
    reason = "omanix's own group (and its members list)";
  }
  {
    option = "loom.switch.watchdog.checks";
    reason = "attrs that only add omanix's desktop checks; the host's own checks merge alongside";
  }
  {
    option = "loom.persist.system.directories";
    reason = "a list that only appends (loom's baseline uses the same rule)";
  }
  {
    option = "systemd.services.omanix-";
    reason = "omanix's own system units (W16: the browser policy writer)";
  }
  {
    option = "systemd.paths.omanix-";
    reason = "omanix's own system path units (W16: the browser color spool)";
  }
  {
    option = "users.groups.omanix-spool";
    reason = "omanix's own group (the human may write the browser color spool)";
  }
]
