# The human's home-manager module. Files HM writes are read-only store links (D9).
# omanix already owns the desktop dotfiles (hypr/*.lua, terminals, fontconfig, …):
# change those through omanix.* options in configuration.nix (`omanix where <file>`
# tells you which).
{ pkgs, ... }:

{
  home.stateVersion = "26.05";
  home.packages = with pkgs; [ ];
}
