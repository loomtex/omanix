# omanix.branding: the About and screensaver text (upstream reads them from
# ~/.config/omarchy/branding/, which is user data; first login seeds them
# from these options when they are set, and never overwrites them).
{ config, lib, ... }:

let
  textOrPath = lib.types.nullOr (lib.types.either lib.types.lines lib.types.path);
in
{
  options.omanix.branding = {
    about = lib.mkOption {
      type = textOrPath;
      default = null;
      example = lib.literalExpression "./branding/about.txt";
      description = "Text (or a file) for the About screen; null keeps the fork's default.";
    };
    screensaver = lib.mkOption {
      type = textOrPath;
      default = null;
      example = lib.literalExpression "./branding/screensaver.txt";
      description = "Text (or a file) the screensaver draws; null keeps the fork's default.";
    };
  };
}
