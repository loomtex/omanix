# apps (§b.2). configure, flash-usb and verify-release are what
# scripts/*.sh exec after their preamble (§e.10); porting-report and
# fork-mirror are developer apps (§f.2.7). None executes anything from an
# omarchy tree.
{ pkgs, omanix }:

let
  inherit (pkgs) lib omanixFork;
  f = omanixFork.forkDir;
  mkApp = drv: { type = "app"; program = lib.getExe drv; };
  tools = import ../lib/tools.nix { inherit pkgs omanix; };
in
{
  configure = mkApp tools.omanix-configure;
  flash-usb = mkApp tools.loom-flash;
  verify-release = { type = "app"; program = "${pkgs.writeShellScript "verify-release" ''
    exec ${lib.getExe tools.omanix-release} verify "$@"
  ''}"; };

  # nix run .#porting-report -- --to <tag|rev> [--json] [--out DIR]
  porting-report = mkApp (pkgs.writeShellApplication {
    name = "porting-report";
    runtimeInputs = with pkgs; [ nix python3 patch jq ];
    text = ''
      to="" json="" out="$PWD/porting-report"
      while (($#)); do
        case $1 in
          --to) to=$2; shift 2 ;;
          --json) json=--json; shift ;;
          --out) out=$2; shift 2 ;;
          *) echo "usage: porting-report --to <tag|rev> [--json] [--out DIR]" >&2; exit 2 ;;
        esac
      done
      [[ -n $to ]] || { echo "usage: porting-report --to <tag|rev> [--json] [--out DIR]" >&2; exit 2; }
      [[ $to =~ ^[A-Za-z0-9._-]+$ ]] || { echo "porting-report: bad ref '$to'" >&2; exit 2; }

      # 1. fetch the target into a fresh, read-only store path
      target=$(nix flake prefetch --json "github:omacom/omarchy/$to" | jq -r .storePath)
      PORTING_TARGET_REF=$to python3 -I ${f}/tools/porting_report.py ${omanixFork.src} "$target" ${f} "$out" $json
    '';
  });

  # nix run .#fork-mirror -- <dir> [--sign]: a plain git repo of the divergence
  # (upstream at the pin, then one commit per stage). Regenerated per release.
  fork-mirror = mkApp (pkgs.writeShellApplication {
    name = "fork-mirror";
    runtimeInputs = with pkgs; [ git python3 coreutils ];
    text = ''
      dir=''${1:?usage: fork-mirror <dir> [--sign]}
      sign=()
      [[ ''${2:-} == --sign ]] && sign=(-S)
      [[ ! -e $dir ]] || { echo "fork-mirror: $dir exists" >&2; exit 1; }
      mkdir -p "$dir"
      cp -r --no-preserve=ownership ${omanixFork.src}/. "$dir"
      chmod -R u+w "$dir"
      cd "$dir"
      git init -q -b master
      commit() { git add -A && git commit -q "''${sign[@]}" -m "$1"; }
      commit "omarchy ${omanixFork.upstream.tag} (${omanixFork.upstream.rev})"
      python3 -I ${f}/tools/assemble.py drop . ${f}/drop.txt
      commit "omanix: drop (fork/drop.txt)"
      python3 -I ${f}/tools/assemble.py add . ${f}/add ${omanixFork.src}
      commit "omanix: add (fork/add)"
      for p in ${f}/patches/*.patch; do
        git apply --whitespace=nowarn "$p"
        commit "omanix: $(basename "$p" .patch)"
      done
      python3 -I ${f}/tools/assemble.py rewrite . ${f}/rewrite.toml
      commit "omanix: rewrite (fork/rewrite.toml)"
      git log --oneline | head -20
    '';
  });
}
