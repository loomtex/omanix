# Browser policy (§f.2.3 RE-EXPRESS, §f.5).
#
# Static policy: upstream's default/chromium/policies/omarchy.json and
# default/firefox/policies.json as programs.chromium.extraOpts and
# programs.firefox.policies.
#
# Theme color: omarchy writes color.json into the managed-policy directories
# as root (NOPASSWD sudo or pkexec). omanix has no such rule: the
# omarchy-theme-set-browser-policy override (fork/add) writes "#rrggbb" into
# /var/lib/omanix/spool/browser-color (group omanix-spool: the human), and
# the root path unit below validates it against ^#[0-9a-f]{6}$ and writes
# color.json into the policy directories that exist, upstream's fixed list.
# The service also runs at boot (the tmpfs root forgets /etc).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  user = config.loom.user.name;
  up = pkgs.omanixFork.src;

  spool = "/var/lib/omanix/spool";
  applied = "/run/omanix/browser-color.applied";
  policyDirs = [
    "/etc/chromium/policies/managed"
    "/etc/opt/chrome/policies/managed"
    "/etc/opt/edge/policies/managed"
    "/etc/brave/policies/managed"
  ];

  publish = pkgs.writeShellScript "omanix-browser-policy" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    f=${spool}/browser-color
    # a regular file the human wrote; anything else is ignored
    [ -f "$f" ] && [ ! -L "$f" ] || exit 0
    c=$(timeout 2 head -c 16 -- "$f" | tr -d '\n')
    if [[ ! $c =~ ^#[0-9a-f]{6}$ ]]; then
      echo "ignoring $f: not #rrggbb" >&2
      exit 0
    fi
    rc=0
    for d in ${lib.escapeShellArgs policyDirs}; do
      [ -d "$d" ] && [ ! -L "$d" ] || continue
      printf '{"BrowserThemeColor": "%s", "BrowserColorScheme": "device"}\n' "$c" > "$d/.color.json.new" &&
        chmod 0644 "$d/.color.json.new" && mv -f "$d/.color.json.new" "$d/color.json" || rc=1
    done
    printf '%s\n' "$c" > ${applied}.new && mv -f ${applied}.new ${applied}
    exit $rc
  '';
in
{
  config = lib.mkIf cfg.enable {
    programs.chromium = {
      enable = lib.mkDefault true;
      extraOpts = lib.mkDefault (lib.importJSON "${up}/default/chromium/policies/omarchy.json");
    };
    programs.firefox.policies = lib.mkDefault (lib.importJSON "${up}/default/firefox/policies.json").policies;

    users.groups.omanix-spool.members = [ user ];
    systemd.tmpfiles.rules = [
      "d /var/lib/omanix 0755 root root -"
      "d ${spool} 0770 root omanix-spool -"
    ];
    loom.persist.system.directories = [
      { directory = spool; user = "root"; group = "omanix-spool"; mode = "0770"; }
    ];

    systemd.paths.omanix-browser-policy = {
      description = "omanix: watch the browser theme color spool";
      wantedBy = [ "paths.target" ];
      pathConfig.PathChanged = "${spool}/browser-color";
    };
    systemd.services.omanix-browser-policy = {
      description = "omanix: write the browser theme color policy";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${publish}";
        ProtectSystem = "strict";
        ReadWritePaths = map (d: "-${d}") policyDirs ++ [ "/run/omanix" ];
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = "none";
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";
        UMask = "0022";
      };
    };
  };
}
