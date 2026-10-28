# Titlebars for omarchy's floating workspace mode (a hyprbars-API plugin; its
# Lua namespace stays hl.plugin.hyprbars). A plugin only loads into the exact
# Hyprland it was built against, so hosts build it with
# `.override { hyprland = config.omanix.hyprland.package; }` (§f.2.9). The
# shipped Lua loads it from /etc/omanix/hyprland-titlebars.so (rewrite.toml).
{ lib, hyprlandPlugins, fetchFromGitHub, cmake, hyprland-omarchy, hyprland ? hyprland-omarchy }:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "omarchy-hyprland-titlebars";
  version = "0.2.2";
  inherit hyprland;

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omarchy-hyprland-titlebars";
    tag = "v0.2.2";
    hash = "sha256-K7IHVqS0HHkJM/ytq1YF+seWB4tEs80eFJK8TAHbqbQ=";
  };

  nativeBuildInputs = [ cmake ];

  passthru.pluginPath = "lib/omarchy-hyprland-titlebars/titlebars.so";

  meta = {
    description = "Titlebars for omarchy's floating workspace mode";
    homepage = "https://github.com/omacom/omarchy-hyprland-titlebars";
    license = with lib.licenses; [ bsd3 mit ];
    platforms = lib.platforms.linux;
  };
}
