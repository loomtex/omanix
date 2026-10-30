# omanix.approval: the human's approval prompter is the shell's card (K6,
# §h.4). nuketown's broker runs omanix-approval-prompt for every request; it
# hands the request directory to the omanix.approval plugin and falls back to
# zenity (nuketown's renderer) when the shell isn't there. Also the Change
# password tool (§h.11): omanix-passwd takes the new password on stdin from
# the plugin's dialog.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  user = config.loom.user.name;
  hmBroker = config.home-manager.users.${user}.nuketown.approvalDaemon or { };

  prompt = pkgs.omanix-approval-prompt.override { renderer = hmBroker.renderer or null; };

  passwd = pkgs.writeShellApplication {
    name = "omanix-passwd";
    runtimeInputs = with pkgs; [ coreutils git jq mkpasswd sops cfg.cli.package ];
    text = ''
      # omanix-passwd: the Change password dialog's helper (human only). The
      # password arrives on stdin and goes to mkpasswd and sops on stdin.
      if [[ -r /etc/loom/cli.json ]] && jq -e --argjson u "$(id -u)" '(.agentUids // []) | index($u)' /etc/loom/cli.json >/dev/null; then
        echo "omanix-passwd: the human's own tool; agents can't run it" >&2; exit 2
      fi
      # The human's working copy (~/omanix-host), cloned from the mirror on
      # demand; the hash goes through `omanix secret set` (encrypt-only).
      repo=''${OMANIX_HOST_REPO:-$(omanix repo path --ensure)}
      [[ -d $repo/.git ]] || { echo "No working copy of the host repo at $repo (omanix repo open)." >&2; exit 1; }
      IFS= read -r pw || { echo "no password on stdin" >&2; exit 2; }
      (( ''${#pw} >= 8 )) || { echo "Use at least 8 characters." >&2; exit 2; }
      hash=$(printf '%s\n' "$pw" | mkpasswd --method=yescrypt --stdin)
      unset pw
      cd "$repo"
      printf '%s' "$hash" | omanix secret set user password_hash --repo "$repo" >/dev/null
      git add secrets/user.yaml
      git commit -q -m "user: change the login password"
      exec omanix propose --repo "$repo" --request "Change my login password"
    '';
  };
in
{
  options.omanix.approval.prompter = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Use the shell's approval card (omanix-approval-prompt) as the human's nuketown prompter. false keeps nuketown's built-in zenity dialog.";
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${user}.nuketown.approvalDaemon.prompter =
      lib.mkIf (cfg.approval.prompter && config.loom.agent.enable) (lib.mkDefault "${prompt}/bin/omanix-approval-prompt");
    environment.systemPackages = [ passwd ];
  };
}
