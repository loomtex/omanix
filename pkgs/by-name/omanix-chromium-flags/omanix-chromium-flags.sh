# omanix-chromium-flags [-0]: the flags the omanix chromium wrapper passes,
# one per line (NUL-separated with -0). Read like Arch's chromium launcher
# reads ~/.config/chromium-flags.conf (whitespace-separated, `#` comments),
# from the read-only HM file and then the runtime overlay (§f.4.2, §f.5).
# Chromium honours only the last --enable-features / --disable-features, so
# their lists are merged into one flag each, in order, without duplicates.

sep='\n'
[[ ${1-} == -0 ]] && sep='\0'

files=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/chromium-flags.conf"
  "${XDG_STATE_HOME:-$HOME/.local/state}/omanix/overlay/chromium-flags.conf"
)

flags=()
enable=()
disable=()

add_list() { # add_list <array name> <comma list>
  local -n list=$1
  local item have
  local -a items
  IFS=, read -ra items <<<"$2"
  for item in "${items[@]}"; do
    [[ -n $item ]] || continue
    for have in "${list[@]}"; do [[ $have == "$item" ]] && continue 2; done
    list+=("$item")
  done
}

for f in "${files[@]}"; do
  [[ -r $f ]] || continue
  while IFS= read -r line || [[ -n $line ]]; do
    line=$(sed -E 's/(^|[[:space:]])#.*$//' <<<"$line")
    read -ra words <<<"$line"
    for w in "${words[@]}"; do
      case $w in
        --enable-features=*) add_list enable "${w#*=}" ;;
        --disable-features=*) add_list disable "${w#*=}" ;;
        *) flags+=("$w") ;;
      esac
    done
  done <"$f"
done

if (( ${#enable[@]} )); then flags+=("--enable-features=$(IFS=,; echo "${enable[*]}")"); fi
if (( ${#disable[@]} )); then flags+=("--disable-features=$(IFS=,; echo "${disable[*]}")"); fi

for w in "${flags[@]}"; do printf "%s$sep" "$w"; done
