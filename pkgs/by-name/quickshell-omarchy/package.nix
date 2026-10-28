# Quickshell at the commit omarchy ships (0.3.2 + 7: hyprland ipc follows
# workspace-id changes, lock state, screencopy and desktop-entry fixes). The
# Qt 6.11 QML-scanner patch (vendored from omarchy-pkgs, MIT) applies only on
# Qt 6.11; nixos-unstable has 6.12 (§f.2.9, facts §3).
{ lib, quickshell, fetchFromGitHub, qt6 }:

let
  rev = "2b4501a282689792b62e94f3fb30d8f512324fe6";
in
quickshell.overrideAttrs (old: {
  pname = "quickshell-omarchy";
  version = "0.3.2-unstable-2b4501a";
  src = fetchFromGitHub {
    owner = "quickshell-mirror";
    repo = "quickshell";
    inherit rev;
    hash = "sha256-tq6x6CRG8Qikrjri59tzu9+b2gri8TjnShkGeh8kUgQ=";
  };
  patches = (old.patches or [ ])
    ++ lib.optional (lib.versions.majorMinor qt6.qtbase.version == "6.11") ./load_qtquick_611.patch;
  cmakeFlags = map
    (f: if lib.hasPrefix "-DGIT_REVISION:" f then lib.cmakeFeature "GIT_REVISION" rev else f)
    old.cmakeFlags;
})
