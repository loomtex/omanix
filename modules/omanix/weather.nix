# omanix.weather.geoUrl: P17 made the weather panel's IP geolocation opt-in.
# Unset (the default) means no lookup through an omarchy service; the panel
# falls back to wttr.in's own lookup or a location the human sets.
{ config, lib, ... }:

let
  cfg = config.omanix;
in
{
  options.omanix.weather.geoUrl = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "https://geo.example.org/";
    description = "Geolocation endpoint for the weather panel (exported as OMANIX_WEATHER_GEO_URL); null disables it.";
  };

  config = lib.mkIf (cfg.enable && cfg.weather.geoUrl != null) {
    environment.sessionVariables.OMANIX_WEATHER_GEO_URL = cfg.weather.geoUrl;
  };
}
