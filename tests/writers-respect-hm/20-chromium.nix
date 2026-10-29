# The chromium case runs the wrapped browser (omanix.apps.chromium.package).
{ config, pkgs, ... }:
{
  environment.systemPackages = [ config.omanix.apps.chromium.package pkgs.omanix-chromium-flags ];
}
