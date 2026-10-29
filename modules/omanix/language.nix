# omanix.language: the shell and menu language (upstream's default/i18n
# registry). Written to $OMARCHY_PATH/default/omanix/language, which
# OMARCHY_LANGUAGE_FILE points at; picking a language is an intent, not a
# runtime writer.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  # The registry is the fork's i18n directory (read at eval time; data only).
  available = builtins.attrNames (lib.filterAttrs (_: t: t == "directory")
    (builtins.readDir "${pkgs.omanixFork.src}/default/i18n"));
in
{
  options.omanix.language = lib.mkOption {
    type = lib.types.enum available;
    default = "en";
    example = "de";
    description = "Language of the shell, menu and keybinding descriptions (a directory of upstream's default/i18n).";
  };
}
