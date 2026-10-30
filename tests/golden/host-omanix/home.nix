# The human's home-manager module (plain HM). Files HM writes are read-only
# store links (D9).
{ pkgs, ... }:

{
  home.stateVersion = "26.05";
  home.packages = with pkgs; [ ];
}
