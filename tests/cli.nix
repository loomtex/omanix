# W19's VM tests: the omanix CLI against a real host repo, offline. One node
# (the template host's base: loom + nuketown + the omanix desktop, loom's
# approval stub answering cards), four variants:
#
#   cli-contract    every command, as the resident and as the human, with
#                   `--help --json` and with `--json`: one JSON envelope,
#                   exit code 0-5 and the command's output schema (§h.8).
#   cli-e2e         the resident's loop: context → set → check → commit →
#                   propose → the card (git diff and nvd computed by root,
#                   the review) → the human's denial reaches the resident.
#   try-preview     `omanix try` previews an allow-listed key in the human's
#                   Hyprland session; `") io.popen(` and a path outside
#                   catalog/preview.json are refused by the session helper.
#   plugin-fixture  `omanix plugin add` of a local fixture flake: one nixpkgs
#                   lock node (U29), the HM half evaluates through inputs
#                   (U30), the persist audit asks for /var/lib/private/<svc>
#                   until `omanix persist add` (U32), and the card flags
#                   "flake.lock: adds input fixture".
#
# The host repo is tests/fixtures/cli-host-src (templates/host + a test stub), locked to
# this omanix source; the VM holds every flake source and the build inputs
# of the derivations a commit changes (tests/lib/host-repo.nix).
{ pkgs, loom, omanix, variant }:

let
  inherit (pkgs) lib;
  hr = import ./lib/host-repo.nix { inherit lib omanix; };
  template = ../templates/host;
  user = "alice";
  uid = "1000";

  pluginFlake = (import ./fixtures/plugin/flake.nix).outputs { self = { }; nixpkgs = omanix.inputs.nixpkgs; };

  # What the VM's `nix eval` of a commit gives, prebuilt here: the same
  # files (tests/fixtures/cli-host-src) and the same inputs.
  hostSrc = ./fixtures/cli-host-src;
  mkRef = extra: homeExtra: omanix.lib.mkHost {
    self = hostSrc;
    inputs = { inherit omanix; inherit (omanix.inputs) nixpkgs home-manager; };
    modules = [ (hostSrc + "/configuration.nix") ] ++ extra;
    homeModules = [ (hostSrc + "/home.nix") ] ++ homeExtra;
  };
  before = mkRef [ ] [ ];
  afterSet = mkRef [ { omanix.hyprland.gdkScale = 1; } ] [ ];
  afterPlugin = mkRef [ pluginFlake.nixosModules.default { loom.persist.system.directories = [ "/var/lib/private/omanix-fixture" ]; } ]
    [ pluginFlake.homeModules.default ];
  docSupport = (pkgs.nixosOptionsDoc { options = { }; }).optionsJSON.inputDerivation;

  hostLock = pkgs.writeText "flake.lock" (builtins.toJSON (hr.lock { }));
  pluginLock = pkgs.writeText "plugin-flake.lock" (builtins.toJSON {
    version = 7;
    root = "root";
    nodes = {
      root.inputs.nixpkgs = "nixpkgs";
      nixpkgs = {
        locked = { type = "path"; path = omanix.inputs.nixpkgs.outPath; narHash = omanix.inputs.nixpkgs.narHash; };
        original = { type = "github"; owner = "nixos"; repo = "nixpkgs"; ref = "nixos-unstable"; };
      };
    };
  });

  # The host repo's first commit: the template, the test stub module, the lock.
  hostTree = pkgs.runCommand "omanix-cli-host" { } ''
    cp -r ${hostSrc} $out
    chmod -R u+w $out
    cp ${hostLock} $out/flake.lock
  '';
  pluginTree = pkgs.runCommand "omanix-plugin-fixture" { } ''
    mkdir $out
    cp ${./fixtures/plugin/flake.nix} $out/flake.nix
    cp ${pluginLock} $out/flake.lock
  '';

  contract = "${pkgs.python3}/bin/python3 -I ${../pkgs/by-name/omanix-cli/omanix_cli/contract.py}";
in
(pkgs.testers.runNixOSTest {
  name = "omanix-${variant}";
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom omanix; };

  nodes.machine = { config, lib, pkgs, ... }: {
    imports = [
      loom.nixosModules.default
      (loom.lib.mkHostModule { self = template; homeModules = [ (template + "/home.nix") ]; hostInputs = { }; system = "x86_64-linux"; })
      omanix.nixosModules.default
      (template + "/configuration.nix")
      { users.allowNoPasswordLogin = true; }
      (loom.outPath + "/tests/vm/disk-standin.nix")
      (loom.outPath + "/tests/lib/approval-stub.nix")
    ];
    networking.hostName = lib.mkForce "machine";
    users.users.${user}.password = "test";
    omanix.session.autologin = lib.mkForce (variant == "try-preview" || variant == "cli-contract");
    omanix.welcome.autoOpen = false;
    loom.agent.harness = lib.mkForce "replay";
    loom.chat.replay.script = pkgs.writeText "cli.jsonl" ''
      {"on": "user"}
      {"text": "ok"}
    '';
    loom.switch.watchdog.timeout = 20;

    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      substituters = lib.mkForce [ ];
      flake-registry = "";
    };
    nix.registry = lib.mkForce { };
    environment.systemPackages = [ pkgs.git pkgs.jq pkgs.socat ];
    system.extraDependencies = hr.sources omanix
      ++ [ hostTree pluginTree docSupport ]
      ++ hr.support before pkgs
      ++ lib.optionals (variant == "cli-e2e" || variant == "cli-contract") (hr.support afterSet pkgs)
      ++ lib.optionals (variant == "plugin-fixture") (hr.support afterPlugin pkgs);

    virtualisation.memorySize = 6144;
    virtualisation.cores = 4;
    virtualisation.diskSize = lib.mkForce 8192;
    virtualisation.writableStoreUseTmpfs = false;
    virtualisation.qemu.options = [ "-vga none" "-device virtio-gpu-pci" ];
  };

  testScript = ''
    import json

    REG = json.load(open("${../pkgs/by-name/omanix-cli/commands.json}"))
    MIRROR = None

    def sh(cmd, timeout=900):
        return machine.succeed(cmd, timeout=timeout)

    def run_as(who, cmd, stdin=None, timeout=1800):
        """(rc, stdout) of cmd as `who` in a login shell; stderr goes to the log."""
        script = f"/tmp/run-{who}.sh"
        machine.succeed(f"cat > {script} <<'EOF'\n{cmd}\nEOF\nchmod 755 {script}")
        redir = f" < {stdin}" if stdin else " < /dev/null"
        rc, out = machine.execute(f"su - {who} -c 'bash {script}'{redir} 2>/tmp/err-{who}", timeout=timeout)
        err = machine.succeed(f"cat /tmp/err-{who}")
        if err.strip():
            print(f"[{who} stderr] {err[-3000:]}")
        return rc, out

    def ada(cmd, **kw):
        return run_as("ada", "cd ~/projects/host && " + cmd, **kw)

    def human(cmd, **kw):
        env = "export XDG_RUNTIME_DIR=/run/user/${uid}; "
        return run_as("${user}", env + cmd, **kw)

    def j(rc_out, want=0):
        rc, out = rc_out
        assert rc == want, f"exit {rc} (wanted {want}):\n{out[-3000:]}"
        return json.loads(out)

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("nuketown-broker.service", "${user}")
    sw = json.loads(sh("cat /etc/loom/switch.json"))
    MIRROR = sw["mirror"]

    with subtest("setup: the host repo (commit A) in the mirror and in ada's clone"):
        sh(f"""
          set -e
          export HOME=/root
          git config --global user.name Test; git config --global user.email test@example
          git config --global init.defaultBranch master; git config --global safe.directory '*'
          cp -r ${hostTree} /root/host && chmod -R u+w /root/host && cd /root/host
          git init -q && git add -A && git commit -qm "A: installed"
          mkdir -p $(dirname {MIRROR}) && git init -q --bare {MIRROR} && git push -q {MIRROR} master
          chmod -R a+rX {MIRROR}
          mkdir -p /persist/var/lib/loom/firstboot && touch /persist/var/lib/loom/firstboot/repo-publish.done
        """)
        rc, out = run_as("ada", f"""
          set -e
          git clone -q {MIRROR} ~/projects/host
          cd ~/projects/host && git config user.name ada && git config user.email ada@machine && git config commit.gpgsign false
        """)
        assert rc == 0, out
        sh("echo approve > /run/loom-test/answer")

    ${{
      cli-e2e = ''
        with subtest("context: the deployed commit, the catalogs and the skills"):
            c = j(ada("omanix context --json"))
            a = sh(f"git -C {MIRROR} rev-parse master").strip()
            assert c["workingCopy"]["head"] == a and c["workingCopy"]["deployed"] == a, c["workingCopy"]
            assert c["workingCopy"]["ahead"] == 0 and c["workingCopy"]["dirty"] == [], c["workingCopy"]
            assert "options/nixos.json" in c["catalog"]["files"] and "host.md" in c["catalog"]["files"], c["catalog"]
            assert len(c["skills"]) == 22 and "omanix-host" in c["skills"], c["skills"]
            assert c["enrollment"]["published"] is True
            assert c["host"]["agent"] == "ada"

        with subtest("set: appended under the marker of configuration.nix, evaluated"):
            w = j(ada("omanix where omanix.hyprland.gdkScale --json"))
            assert w["kind"] == "option" and all(d["origin"]["kind"] != "host" for d in w["definitions"]), w
            s = j(ada("omanix set omanix.hyprland.gdkScale 1 --json"))
            assert s["action"] == "appended" and s["file"] == "configuration.nix" and s["value"] == 1, s
            assert s["shadowedBy"] == [], s
            diff = ada("git diff")[1]
            print(diff)
            assert "+  omanix.hyprland.gdkScale = 1;" in diff, diff
            w = j(ada("omanix where omanix.hyprland.gdkScale --json"))
            host = [d for d in w["definitions"] if d["origin"]["kind"] == "host"]
            assert len(host) == 1 and host[0]["editable"] and host[0]["where"].startswith("configuration.nix:"), w
            # a second set rewrites that line in place
            s = j(ada("omanix set omanix.hyprland.gdkScale 1 --json"))
            assert s["action"] == "unchanged", s

        with subtest("check: evaluates, the key files match keys.nix, builds"):
            ck = j(ada("omanix check --json", timeout=3600))
            assert ck["eval"]["ok"] and ck["keysSync"]["ok"] and ck["build"]["ok"], ck
            out = ck["build"]["out"]
            assert '"gdkScale": 1' in sh(f"cat {out}/catalog/config.json")

        with subtest("propose: the card shows the request, the diff and nvd; the denial reaches the resident"):
            sh("echo 'deny:not today' > /run/loom-test/answer")
            assert ada("git commit -qam 'look: smaller GDK scale' && echo ok")[0] == 0
            p = j(ada("omanix propose --request 'make everything smaller' --json", timeout=3600), want=1)
            assert p["result"] == "denied" and "not today" in p["log"], p
            d = sh("ls -1td /run/loom-test/prompts/*/ | head -1").strip()
            req = json.loads(sh(f"cat {d}request.json"))
            card = json.loads(sh(f"cat {d}kind/card.json"))
            assert req["kind"]["name"] == "loom-switch" and req["requester"] == "ada", req
            assert card["request"] == "make everything smaller", card
            assert "omanix.hyprland.gdkScale = 1" in sh(f"cat {d}kind/diff.txt")
            sh(f"test -s {d}kind/nvd.txt")
            view = json.loads(sh(f"loom-review-view {d}"))
            print(view)
            assert view["form"] in ("routine", "full"), view
      '';

      cli-contract = ''
        def contract(group, name, out, rc, help=False):
            sh(f"cat > /tmp/out.json <<'EOF'\n{out}\nEOF")
            r, msg = machine.execute(f"${contract} ${../pkgs/by-name/omanix-cli/commands.json} {group} {name} {rc} {'help' if help else '''} < /tmp/out.json")
            assert r == 0, f"{group} {name} (exit {rc}): {msg}\n{out[-2000:]}"

        # minimal arguments per command, and who runs it
        ARGS = {
            ("core", "context"): "", ("core", "options"): "gdkScale", ("core", "where"): "omanix.defaults.terminal",
            ("core", "explain"): "omanix.defaults.terminal", ("core", "set"): "omanix.hyprland.gdkScale 1",
            ("core", "unset"): "omanix.hyprland.gdkScale", ("core", "check"): "--no-build", ("core", "plan"): "",
            ("core", "propose"): "--request 'contract'", ("core", "update"): "", ("core", "status"): "",
            ("core", "doctor"): "", ("core", "why-failed"): "", ("core", "try"): "omanix.hyprland.settings.general.gaps_out 4",
            ("core", "reset"): "font", ("core", "edit"): "--print ~/.config/kitty/kitty.conf", ("core", "intent"): "setup.default.browser.firefox",
            ("plugin", "inspect"): "git+file:///srv/plugin", ("plugin", "add"): "git+file:///srv/plugin --name fixture",
            ("plugin", "remove"): "fixture", ("app", "add"): "hello", ("app", "remove"): "hello",
            ("secret", "set"): "data contract-token", ("persist", "add"): "/var/lib/contract", ("persist", "audit"): "",
            ("hw", "probe"): "", ("repo", "open"): "--print", ("repo", "path"): "--ensure",
        }
        HUMAN = {("core", "doctor"), ("core", "reset"), ("core", "edit"), ("core", "intent"), ("secret", "set"), ("repo", "open"), ("repo", "path")}

        with subtest("fixture plugin repo for the plugin verbs"):
            sh("""
              set -e; export HOME=/root
              cp -r ${pluginTree} /srv/plugin && chmod -R u+w /srv/plugin && cd /srv/plugin
              git init -q && git add -A && git commit -qm plugin && git tag v0.1.0 && chmod -R a+rX /srv/plugin
            """)
            machine.wait_until_succeeds("su - ${user} -c 'XDG_RUNTIME_DIR=/run/user/${uid} /run/current-system/omarchy/bin/omarchy-shell omanix.chat ping' | grep -qx ok", timeout=300)
            sh("echo 'deny:contract' > /run/loom-test/answer")
            assert human("printf s3cret > /tmp/secret && chmod 644 /tmp/secret")[0] == 0

        seen = set()
        for group, cmds in REG["commands"].items():
            for name in cmds:
                words = name if group == "core" else f"{group} {name}"
                who = human if (group, name) in HUMAN else ada
                rc, out = who(f"omanix {words} --help --json")
                assert rc == 0, f"{words} --help --json exit {rc}"
                contract(group, name, out, 0, help=True)
                stdin = "/tmp/secret" if (group, name) == ("secret", "set") else None
                rc, out = who(f"omanix {words} {ARGS[(group, name)]} --json", stdin=stdin, timeout=3600)
                print(f"omanix {words} → exit {rc}")
                assert rc in (0, 1, 2, 3, 4, 5), rc
                contract(group, name, out, rc)
                seen.add((group, name))
                if (group, name) in (("core", "set"), ("app", "add"), ("persist", "add"), ("plugin", "remove")):
                    ada("git checkout -q -- . && git clean -qfd")
        assert len(seen) == sum(len(c) for c in REG["commands"].values())

        with subtest("the resident is refused the human's tools, with exit 2 and a reason"):
            for words in ("secret set data x", "reset --all", "edit hypr/monitors.lua", "doctor", "repo open"):
                d = j(ada(f"omanix {words} --json"), want=2)
                assert d["error"], d
        with subtest("an unknown command is a usage error"):
            d = j(ada("omanix frobnicate --json"), want=2)
            assert "unknown command" in d["error"]
      '';

      try-preview = ''
        import shlex
        HY = "export XDG_RUNTIME_DIR=/run/user/${uid} HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/${uid}/hypr | head -n1); "

        machine.wait_until_succeeds("su - ${user} -c " + shlex.quote(HY + "hyprctl -j monitors"), timeout=300)

        def gaps():
            return json.loads(machine.succeed("su - ${user} -c " + shlex.quote(HY + "hyprctl -j getoption general:gaps_out")))

        with subtest("an allow-listed key previews live, and --reset reverts it"):
            before_ = gaps()
            d = j(human(HY + "omanix try omanix.hyprland.settings.general.gaps_out 37 --json"))
            assert d["delivered"] and "gaps_out → 37" in d["rendered"]["label"], d
            g = gaps()
            assert "37" in json.dumps(g), g
            j(human(HY + "omanix try --reset --json"))
            assert gaps() == before_, gaps()

        with subtest("the session helper refuses values that aren't the key's type, and paths outside preview.json"):
            for path, value in [
                ("omanix.hyprland.settings.general.gaps_out", '"4\\") io.popen(\\"touch /tmp/pwned\\")"'),
                ("omanix.hyprland.settings.general.gaps_out", "9999"),
                ("omanix.hyprland.settings.general.layout", '"dwindle\\") io.popen(\\"id"'),
                ("omanix.hyprland.extraLua", '"io.popen(\\"touch /tmp/pwned\\")"'),
                ("omanix.fonts.monospace", '"x\\") io.popen(\\"id"'),
            ]:
                rc, out = human(HY + f"omanix-preview apply {path} '{value}'")
                assert rc == 2 and json.loads(out)["ok"] is False, (path, value, out)
                d = j(human(HY + f"omanix try {path} '{value}' --json"), want=2)
                assert d["error"], d
            machine.fail("test -e /tmp/pwned")

        with subtest("the resident can't preview by itself: no Wayland, and the bridge relays only what loom allows"):
            d = j(ada("omanix try omanix.hyprland.settings.general.gaps_out 4 --json"), want=5)
            assert d["error"], d
            d = j(ada("omanix try omanix.hyprland.extraLua '\"x\"' --json"), want=2)
      '';

      plugin-fixture = ''
        with subtest("fixture plugin repo, tagged v0.1.0"):
            sh("""
              set -e; export HOME=/root
              cp -r ${pluginTree} /srv/plugin && chmod -R u+w /srv/plugin && cd /srv/plugin
              git init -q && git add -A && git commit -qm plugin && git tag v0.1.0 && chmod -R a+rX /srv/plugin
            """)

        with subtest("inspect: outputs, declared inputs, latest tag"):
            i = j(ada("omanix plugin inspect git+file:///srv/plugin --json"))
            assert i["outputs"]["nixosModules"] == ["default"] and i["outputs"]["homeModules"] == ["default"], i
            assert i["inputs"] == ["nixpkgs"] and i["latestTag"] == "v0.1.0", i

        with subtest("add: the input follows nixpkgs, pinned to the tag; imports in plugins.nix and home.nix"):
            a = j(ada("omanix plugin add git+file:///srv/plugin --name fixture --json"))
            assert a["url"] == "git+file:///srv/plugin?ref=refs/tags/v0.1.0" and a["follows"] == ["nixpkgs"], a
            assert {x["file"] for x in a["imports"]} == {"modules/plugins.nix", "home.nix"}, a
            assert a["lockNodes"] == ["fixture"], a
            print(ada("git diff")[1])
            lock = json.loads(ada("cat flake.lock")[1])
            np = [n for n, v in lock["nodes"].items() if v.get("original", {}).get("repo") == "nixpkgs" or n.startswith("nixpkgs")]
            assert np == ["nixpkgs"], f"U29: nixpkgs nodes {np}"
            assert lock["nodes"]["fixture"]["inputs"]["nixpkgs"] == ["nixpkgs"], lock["nodes"]["fixture"]

        with subtest("U32: the persist audit wants /var/lib/private/omanix-fixture until persist add"):
            ck = j(ada("omanix check --no-build --json"), want=1)
            msgs = " ".join(ck["eval"]["failed"])
            assert "/var/lib/private/omanix-fixture" in msgs and "is not persisted" in msgs, ck
            p = j(ada("omanix persist add /var/lib/private/omanix-fixture --json"))
            assert p["changed"] and p["file"] == "modules/persist.nix", p

        with subtest("U30: the HM half evaluates through home.nix's inputs; the host builds"):
            v = ada("nix eval --raw .#nixosConfigurations.host.config.home-manager.users.${user}.home.file.'\".omanix-fixture\"'.text")
            assert v[0] == 0 and v[1].strip() == "from the plugin fixture", v
            ck = j(ada("omanix check --json", timeout=3600))
            assert ck["build"]["ok"], ck

        with subtest("the card flags the new input"):
            sh("echo 'deny:just looking' > /run/loom-test/answer")
            assert ada("git add -A && git commit -qm 'plugin: fixture' && echo ok")[0] == 0
            p = j(ada("omanix propose --request 'add the fixture plugin' --json", timeout=3600), want=1)
            assert p["result"] == "denied", p
            d = sh("ls -1td /run/loom-test/prompts/*/ | head -1").strip()
            card = json.loads(sh(f"cat {d}kind/card.json"))
            assert "flake.lock: adds input fixture" in card["flags"], card
            view = json.loads(sh(f"loom-review-view {d}"))
            assert view["form"] == "full", view

        with subtest("remove: imports, input and lock node go"):
            r = j(ada("omanix plugin remove fixture --json"))
            assert "flake.lock: fixture" in r["removed"], r
            assert "fixture" not in ada("cat modules/plugins.nix home.nix flake.nix")[1]
      '';
    }.${variant}}
  '';
}) // { inherit hostTree before afterSet afterPlugin; }   # for debugging the offline build set
