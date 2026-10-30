# omanix.chat: the chat panel's side of the resident (§h.3). The panel itself
# is the fork's shell/plugins/omanix-chat (W18); this writes what it reads:
# /etc/omanix/chat.json (the agent, its socket, the attachment limit),
# /etc/omanix/chips/rules.json (data/chips/rules.json, §h.6) and
# omanix-chat-facts, the local facts the suggestion chips are computed from.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  agent = config.loom.agent;
  enabled = agent.enable && (config.loom.chat.enable or true);

  # Local state only, in the human's session; nothing from the agent.
  facts = pkgs.writeShellApplication {
    name = "omanix-chat-facts";
    runtimeInputs = with pkgs; [ coreutils jq systemd findutils ];
    text = ''
      state=''${XDG_STATE_HOME:-$HOME/.local/state}
      runtime=/run/omanix/session/$(id -u)/runtime.json
      first=$state/omanix/done/first-login
      days=999
      [[ -e $first ]] && days=$(( ($(date +%s) - $(stat -c %Y "$first")) / 86400 ))
      failed=$( { systemctl --failed --plain --no-legend 2>/dev/null; systemctl --user --failed --plain --no-legend 2>/dev/null; } \
        | awk '{print $1}' | head -n 4 | jq -R . | jq -sc .)
      update=false
      [[ -s /var/lib/loom/update/available ]] && update=true
      # loom-switch's records (recordsDir in /etc/loom/switch.json): a
      # watchdog rollback in the last hour.
      records=$(jq -r '.recordsDir // "/var/lib/loom/switches"' /etc/loom/switch.json 2>/dev/null || echo /var/lib/loom/switches)
      rolled=false
      if find "$records" -maxdepth 2 -name result.json -mmin -60 2>/dev/null \
          | xargs -r grep -l '"status": *"rolled-back"' 2>/dev/null | grep -q .; then rolled=true; fi
      overlays='[]'
      if [[ -r $runtime ]]; then
        # the theme is runtime state too: it differs from the declared one
        # after the picker (make it stick, §f.4.6)
        declared=$(jq -r '.omanix.theme.default // ""' /run/current-system/catalog/config.json 2>/dev/null || true)
        overlays=$(jq -c --arg declared "$declared" '([.overlays // {} | to_entries[] | select(.value.empty == false) | .key
          | if startswith("hypr/monitors") then "monitors" elif startswith("hypr/input") or . == "xcompose" then "input"
            elif test("^(alacritty|kitty|ghostty|foot)|fontconfig") then "font" elif startswith("hypr/looknfeel") or startswith("gtk4") then "look"
            else "hypr" end]
          + (if (.theme // "") != "" and $declared != "" and ((.theme | ascii_downcase | gsub(" "; "-")) != $declared) then ["theme"] else [] end))
          | unique' "$runtime")
      fi
      jq -cn --argjson f "$failed" --argjson u "$update" --argjson r "$rolled" --argjson o "$overlays" --argjson d "$days" \
        '{failedUnits: $f, updatePending: $u, rolledBackRecently: $r, overlays: $o, daysSinceFirstLogin: $d, newDevices: []}'
    '';
  };
in
{
  options.omanix.chat = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      defaultText = lib.literalExpression "config.omanix.enable";
      description = "Whether the shell's agent chat panel (omanix.chat) is configured; without an agent it shows the Do-it-yourself views.";
    };
  };

  config = lib.mkIf cfg.chat.enable {
    environment.etc."omanix/chat.json".text = builtins.toJSON {
      agent = if enabled then agent.name else "";
      socket = if enabled then "/run/loom/chat/${agent.name}.sock" else "";
      maxBytes = agent.chat.attachments.maxBytes or 8388608;
    };
    environment.etc."omanix/chips/rules.json".source = ../../data/chips/rules.json;
    environment.systemPackages = [ facts ];
  };
}
