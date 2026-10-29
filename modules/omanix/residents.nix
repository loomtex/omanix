# The residents on the omanix desktop (§a.3 C5, §h):
# - the approval broker restarts inside the graphical session, so it sees
#   WAYLAND_DISPLAY (loom.agent.restartBrokerWithSession);
# - the human's approval prompter is omanix's. Until W18's
#   omanix-approval-prompt (the Quickshell card) lands, it is a stub: a
#   zenity question built from the request dir, same contract (exit 0 =
#   approve);
# - the resident may read the typed runtime summary (group omanix-resident,
#   runtime.nix).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  agent = config.loom.agent;
  user = config.loom.user.name;

  prompterStub = pkgs.writeShellScript "omanix-approval-prompt-stub" ''
    # omanix: placeholder for omanix-approval-prompt (W18).
    set -uo pipefail
    dir=$1
    text=$(${pkgs.jq}/bin/jq -r '
      def esc: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
      "<b>\(.requester // "?" | esc)</b> asks to run as \(.runAs // "root" | esc):\n\n<tt>\(.display // (.argv | join(" ")) | esc)</tt>"
      + (if .why then "\n\nWhy (their words): \(.why | esc)" else "" end)
    ' "$dir/request.json") || exit 1
    review=$(${pkgs.jq}/bin/jq -r '
      def esc: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
      if .summary then "\n\nReviewer (\(.risk // "?")): \(.summary | esc)" else "" end
    ' "$dir/review.json" 2>/dev/null) || review=""
    exec ${pkgs.zenity}/bin/zenity --question --title="omanix: approve?" \
      --text="$text$review" --ok-label=Approve --cancel-label=Deny --default-cancel \
      --width=640 --timeout=120
  '';
in
{
  config = lib.mkIf (cfg.enable && agent.enable) {
    loom.agent.restartBrokerWithSession = lib.mkDefault true;
    users.groups.omanix-resident.members = [ agent.name ];
    home-manager.users.${user}.nuketown.approvalDaemon.prompter = lib.mkDefault "${prompterStub}";
  };
}
