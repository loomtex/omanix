# omanix-approval-prompt <request dir> (K6, DESIGN §h.4): nuketown's broker
# runs it for every approval request. It hands the directory to the shell's
# omanix.approval plugin (`omarchy-shell omanix.approval show <dir>`), which
# draws the card, and waits for the decision the plugin writes under
# $XDG_RUNTIME_DIR/omanix-approval/<id>/. Exit 0 approves; otherwise the first
# line of stdout is the reason the requester sees. With no shell (or no
# plugin) it asks with zenity instead, rendered by nuketown's own jq renderer.
{
  lib,
  writeShellApplication,
  coreutils,
  gnugrep,
  gnused,
  jq,
  socat,
  zenity,
  quickshell-omarchy,
  renderer ? null, # nuketown.approvalDaemon.renderer (jq program)
}:

writeShellApplication {
  name = "omanix-approval-prompt";
  runtimeInputs = [ coreutils gnugrep gnused jq socat zenity quickshell-omarchy ];
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

    # ---- fallback: zenity (no shell, or the plugin isn't loaded) ---------
    ${if renderer == null then ''
      text="<b>$(jq -r '.requester' "$dir/request.json" | sed 's/&/\&amp;/g; s/</\&lt;/g')</b> asks to run:\n\n<tt>$(jq -r '.display' "$dir/request.json" | head -c 800 | sed 's/&/\&amp;/g; s/</\&lt;/g')</tt>"
    '' else ''
      text=$(jq -rn --slurpfile req "$dir/request.json" --slurpfile rev <(cat "$dir/review.json" 2>/dev/null || true) -f ${renderer}) || exit 1
    ''}
    [[ -n ''${NUKETOWN_PROMPT_NOTE-} ]] && text+="\n\n$NUKETOWN_PROMPT_NOTE"
    files=$(mktemp)
    zpid=""
    trap 'rm -f "$files"; [[ -n $zpid ]] && kill "$zpid" 2>/dev/null; exit 1' TERM INT HUP
    while IFS= read -r -d "" path && IFS= read -r -d "" snap && IFS= read -r -d "" sha; do
      [[ $snap == snapshots/* && $snap != *..* ]] || continue
      {
        printf '==== %s\n==== sha256 %s\n\n' "$path" "$sha"
        head -c 1048576 "$dir/$snap" | cat -n
        printf '\n'
      } >> "$files"
    done < <(jq -j '.snapshots[] | .path, "\u0000", .snapshot, "\u0000", .sha256, "\u0000"' "$dir/request.json")
    for f in "$dir"/kind/{card.json,stat.txt,nvd.txt,diff.txt}; do
      [[ -f $f ]] || continue
      {
        printf '==== %s\n\n' "''${f#"$dir"/}"
        head -c 204800 "$f"
        printf '\n\n'
      } >> "$files"
    done
    extra=(--extra-button "Deny with reason")
    [[ -s $files ]] && extra+=(--extra-button "Show files")
    topt=()
    (( timeout > 0 )) && topt=(--timeout="$timeout")
    outf=$(mktemp)
    while :; do
      zenity --question --title="omanix: approve?" --text="$text" --ok-label=Approve --cancel-label=Deny \
        --default-cancel --width=640 "''${topt[@]}" "''${extra[@]}" > "$outf" 2>/dev/null & zpid=$!
      rc=0; wait "$zpid" || rc=$?; zpid=""
      [[ $rc == 0 ]] && { rm -f "$files" "$outf"; exit 0; }
      case "$(cat "$outf")" in
        "Show files") zenity --text-info --title="omanix: files in this request" --filename="$files" --width=900 --height=700 2>/dev/null; continue ;;
        "Deny with reason")
          zenity --entry --title="omanix: deny" --text="Reason (shown to the requester):" --width=500 2>/dev/null | head -c 500
          rm -f "$files"; exit 1 ;;
      esac
      [[ $rc == 5 ]] && echo "no answer within ''${timeout}s"
      rm -f "$files"
      exit 1
    done
  '';
  meta.description = "nuketown approval prompter that draws the omanix approval card";
}
