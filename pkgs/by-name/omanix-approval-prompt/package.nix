# omanix-approval-prompt <request dir> (K6, DESIGN §h.4): nuketown's broker
# runs it for every approval request. It hands the directory to the shell's
# omanix.approval plugin (`omarchy-shell omanix.approval show <dir>`), which
# draws the card, and waits for the decision the plugin writes under
# $XDG_RUNTIME_DIR/omanix-approval/<id>/. Exit 0 approves; otherwise the first
# line of stdout is the reason the requester sees. With no shell (or no
# plugin) it hands the request to nuketown's own approval card
# (nuketown.approvalDaemon.cardPrompter) instead.
{
  lib,
  writeShellApplication,
  coreutils,
  gnugrep,
  gnused,
  jq,
  socat,
  quickshell-omarchy,
  card ? null, # nuketown.approvalDaemon.cardPrompter (package)
}:

writeShellApplication {
  name = "omanix-approval-prompt";
  runtimeInputs = [ coreutils gnugrep gnused jq socat quickshell-omarchy ];
  text = ''
    dir=''${1:?usage: omanix-approval-prompt <request dir>}
    dir=''${dir%/}
    id=''${dir##*/}
    [[ $id =~ ^[A-Za-z0-9._-]+$ && -r $dir/request.json ]] || { echo "not a request directory"; exit 1; }
    export OMARCHY_PATH=''${OMARCHY_PATH:-/run/current-system/omarchy}
    export XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    shell() { "$OMARCHY_PATH/bin/omarchy-shell" "$@" 2>/dev/null; }

    timeout=$(jq -r '.prompt_timeout // 120' "$dir/request.json")
    [[ $timeout =~ ^[0-9]+$ ]] || timeout=120

    # ---- the card ------------------------------------------------------
    rt=$XDG_RUNTIME_DIR/omanix-approval/$id
    if [[ $(shell omanix.approval ping) == ok ]]; then
      mkdir -p "$rt"
      chmod 700 "$rt"
      rm -f "$rt/decision.json"
      printf '%s\n' "$dir" > "$rt/dir"
      cleanup() { rm -rf "$rt"; }
      # The broker stops us when the request goes away (a touch approved a
      # decrypt, or the requester gave up): take the card down.
      trap 'shell omanix.approval dismiss "$id" >/dev/null; cleanup; exit 1' TERM INT HUP
      if [[ $(shell omanix.approval show "$dir") == ok ]]; then
        start=$(date +%s)
        while :; do
          if [[ -s $rt/decision.json ]]; then
            decision=$(jq -r '.decision // "deny"' "$rt/decision.json")
            reason=$(jq -r '.reason // ""' "$rt/decision.json" | tr -d '\000-\037' | head -c 500)
            cleanup
            [[ $decision == approve ]] && exit 0
            printf '%s\n' "$reason"
            exit 1
          fi
          if (( timeout > 0 && $(date +%s) - start >= timeout )); then
            shell omanix.approval dismiss "$id" >/dev/null
            cleanup
            echo "no answer within ''${timeout}s"
            exit 1
          fi
          sleep 0.2
        done
      fi
      cleanup
      trap - TERM INT HUP
    fi

    # ---- fallback: nuketown's approval card (no shell, or no plugin) -----
    # Same contract as this prompter (exit 0 approves, the reason on stdout,
    # "no answer within Ns"); it reads NUKETOWN_PROMPT_NOTE itself. The
    # broker's environment only has DISPLAY: use the session's Wayland
    # socket when there is one.
    ${if card == null then ''
      echo "no approval card: the shell isn't running"
      exit 1
    '' else ''
      if [[ -z ''${WAYLAND_DISPLAY-} ]]; then
        for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
          [[ -S $s && $s != *.lock ]] && { export WAYLAND_DISPLAY=''${s##*/}; break; }
        done
      fi
      exec ${lib.getExe card} "$dir"
    ''}
  '';
  meta.description = "nuketown approval prompter that draws the omanix approval card";
}
