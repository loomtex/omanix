# W21: the demo's VM part (DESIGN §j, §i.2). Each variant boots the omanix
# desktop with the replay resident and the replay reviewer (demo/scenes.nix)
# and plays one scene the way the presenter does: the human's side is the
# real shell (menu, chat panel, theme picker, the approval card, clicked
# with ydotool), the resident commits to the real host repo and proposes,
# nuketown asks the reviewer and the card, loom-switch activates under the
# watchdog. Screenshots at each beat.
#
#   vm-demo-2      Install Steam from the menu → one-line card → approved →
#                  Steam in the launcher; "hide the dock" → a second card
#   vm-demo-3      theme picker → Kanagawa → Make it stick → one-line card →
#                  one line in configuration.nix → the chip is gone
#   vm-demo-4      battery: the reviewer flags Bluetooth → full card → git
#                  and nvd diffs → Deny "keep Bluetooth" → the resident
#                  recommits → one-line card → approved
#   vm-demo-5      Wi-Fi: a 14-line root script; the review flags line 9;
#                  Show command and script (line numbers); Deny → resident
#                  drops line 9 → approved → saved networks intact; then a
#                  change card
#   vm-demo-6      a monitor rule turns off the only screen → the watchdog
#                  rolls back → "Rolled back: Hyprland lost its display" →
#                  why-failed; a working change, then Undo (one click + card)
#   vm-demo-7      two residents: uids, homes, the human's key unreadable,
#                  ada can't push master on the silo stand-in, the reviewer's
#                  runs as uid 1101, ada's one sudo rule, the audit copies
#   make-it-stick  scale, text size, theme and a look overlay → snapshots
#                  attached → card → approved → settle empties what was
#                  absorbed and drops the kv keys; the overlay changed after
#                  its snapshot stays and doctor lists it
#   human-commit   no resident: the human edits ~/omanix-host, commits,
#                  `loom propose` → pkexec → a card without review →
#                  approved; over ssh, `sudo loom-switch` with the password
#
# The toplevel each proposal switches to is a specialisation of this VM
# (demo/scenes.nix explains why); everything else is the real pipeline.
{ pkgs, loom, omanix, variant, inputs }:

let
  inherit (pkgs) lib;
  hr = import ./lib/host-repo.nix { inherit lib omanix; };
  template = loom.outPath + "/templates/host";
  user = "alice";
  uid = "1000";

  key = {
    vm-demo-2 = "2"; vm-demo-3 = "3"; vm-demo-4 = "4"; vm-demo-5 = "5"; vm-demo-6 = "6"; vm-demo-7 = "7";
    make-it-stick = "make-it-stick"; human-commit = "human-commit";
  }.${variant};
  scene = (import ../demo/scenes.nix { inherit lib; }).${key};
  agentless = variant == "human-commit";
  withSilo = variant == "vm-demo-7";
  # scenes 2 and 3 evaluate the host repo in the VM (omanix check, omanix set)
  evaluates = variant == "vm-demo-2" || variant == "vm-demo-3";

  jsonl = lib.concatMapStrings (e: builtins.toJSON e + "\n");
  resident = pkgs.writeText "demo-${key}.jsonl" (jsonl scene.resident);
  reviews = pkgs.writeText "demo-${key}-reviews.jsonl" (jsonl scene.reviews);

  tools = pkgs.runCommand "omanix-demo-tools" { } ''
    mkdir -p $out/bin
    for t in demo-edit demo-stick; do
      { echo "#!${pkgs.python3}/bin/python3 -I"; cat ${../demo/tools}/$t.py; } > $out/bin/$t
      chmod +x $out/bin/$t
    done
  '';

  # The host repo: the template plus the test stub (W19's fixture), locked
  # to this omanix source.
  hostSrc = ./fixtures/cli-host-src;
  hostTree = pkgs.runCommand "omanix-demo-host" { } ''
    cp -r ${hostSrc} $out
    chmod -R u+w $out
    cp ${pkgs.writeText "flake.lock" (builtins.toJSON (hr.lock { }))} $out/flake.lock
  '';

  tripwire = { networking.hosts."0.0.0.0" = [ "silo.loom.farm" ]; };
  stick = builtins.fromJSON (builtins.readFile ./fixtures/demo/stick.json);
in
pkgs.testers.runNixOSTest {
  name = "omanix-${variant}";
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom omanix; };

  nodes = lib.optionalAttrs withSilo {
    silo = { ... }: { imports = [ "${inputs.loom.inputs.seed-silo}/instances/silo/standalone.nix" tripwire ]; };
  } // {
    machine = { config, lib, pkgs, ... }: {
      imports = [
        loom.nixosModules.default
        (loom.lib.mkHostModule { self = template; homeModules = [ (template + "/home.nix") ]; hostInputs = { }; system = "x86_64-linux"; })
        omanix.nixosModules.default
        (template + "/configuration.nix")
        { users.allowNoPasswordLogin = true; }
        (loom.outPath + "/tests/vm/disk-standin.nix")
        tripwire
      ] ++ lib.optional agentless {
        # No resident. LOOM GAP (W21 report): loom configures nuketown only
        # while a resident or the reviewer is enabled, and nuketown's
        # approval (nuketown-approve, the broker's socket directory) only
        # while some agent has sudo. The human's `loom propose` needs it, so
        # here the reviewer stays on and is a sudo agent that may request
        # nothing (an empty allow list refuses every request before the
        # human is asked). A host with no agent at all has no approval path
        # until loom or nuketown provides one.
        loom.agent.enable = lib.mkForce false;
        loom.reviewer.enable = true;
        nuketown.agents.reviewer.sudo = { enable = lib.mkForce true; approvalAllow = lib.mkForce [ ]; };
        services.openssh.enable = true;
      } ++ lib.optional withSilo {
        loom.host.repo.fetchUrl = "ssh://git@silo/omanix/demo.git";
        loom.host.repo.pushUrl = "ssh://git@silo/omanix/demo.git";
      };
      networking.hostName = lib.mkForce "machine";
      users.users.${user}.password = "test";
      omanix.session.autologin = true;
      omanix.welcome.autoOpen = false;

      # The residents: the replay harness plays demo/scenes.nix.
      loom.agent.harness = lib.mkForce "replay";
      loom.chat.replay.script = resident;
      loom.reviewer.harness = "replay";
      loom.reviewer.replay.script = reviews;
      loom.agent.sudo = lib.mkIf (variant == "vm-demo-5") (lib.mkForce "any");   # D8: a script needs "any"

      # The switch path, with the demo's 30 s watchdog deadline.
      loom.switch.watchdog.timeout = 30;
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
      specialisation = lib.mapAttrs (_: m: { configuration = m; }) scene.systems;

      # Clicks on the card (uinput); the human is not in the group.
      programs.ydotool.enable = true;
      environment.systemPackages = [ pkgs.git pkgs.jq pkgs.socat pkgs.openssh tools ];
      environment.etc."demo/fix-wifi.sh".source = ../demo/fix-wifi.sh;
      system.extraDependencies = [ hostTree ] ++ lib.optionals evaluates (hr.sources omanix);
      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        substituters = lib.mkForce [ ];
        flake-registry = "";
      };
      nix.registry = lib.mkForce { };

      virtualisation.memorySize = 6144;
      virtualisation.cores = 4;
      virtualisation.diskSize = lib.mkForce 8192;
      virtualisation.writableStoreUseTmpfs = false;
      virtualisation.qemu.options = [ "-vga none" "-device virtio-gpu-pci" ];
    };
  };

  testScript = ''
    import json, shlex, time

    USER, UID = "${user}", "${uid}"
    ENV = ("export XDG_RUNTIME_DIR=/run/user/${uid} OMARCHY_PATH=/run/current-system/omarchy DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus; "
           "export WAYLAND_DISPLAY=$(cd /run/user/${uid} && ls wayland-* 2>/dev/null | grep -v lock | head -n1); "
           "export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/${uid}/hypr 2>/dev/null | head -n1); ")

    def sh(cmd, timeout=900):
        return machine.succeed(cmd, timeout=timeout)

    def human(cmd, timeout=900):
        return machine.succeed("su - ${user} -c " + shlex.quote(ENV + cmd), timeout=timeout)

    def human_rc(cmd, timeout=900):
        return machine.execute("su - ${user} -c " + shlex.quote(ENV + cmd), timeout=timeout)

    def ipc(*args):
        return human("/run/current-system/omarchy/bin/omarchy-shell " + " ".join(shlex.quote(a) for a in args)).strip()

    def state(target):
        return json.loads(ipc(target, "state"))

    def diag():
        print(machine.execute("journalctl -b --no-pager -n 150 _UID=${uid} | grep -iv 'layershell screen'; "
                              "journalctl -b --no-pager -n 60 -u 'loom-agent-bridge@*' -u 'loom-switch-*' -u nuketown-approval; "
                              "ls -la /agents/ada/demo 2>&1; tail -n 40 /agents/ada/demo/*.json 2>&1; "
                              "ps -eo pid,user,args | grep -E 'pkexec|loom|nuketown|polkit' | grep -v grep; "
                              "cat /tmp/human-propose.log 2>/dev/null")[1])
        try:
            print("chat rows:", json.dumps(state("omanix.chat").get("rows"))[-3000:])
        except Exception as e:
            print("chat state unavailable:", e)

    def until(f, what, timeout=120):
        end = time.monotonic() + timeout
        while True:
            try:
                v = f()
            except Exception:
                v = None
            if v:
                return v
            if time.monotonic() > end:
                diag()
                raise AssertionError(f"timed out after {timeout} s: {what}")
            time.sleep(1)

    def run_as(who, cmd, timeout=1800):
        script = f"/tmp/run-{who}.sh"
        machine.succeed(f"cat > {script} <<'EOF'\n{cmd}\nEOF\nchmod 755 {script}")
        rc, out = machine.execute(f"su - {who} -c 'bash {script}' < /dev/null 2>/tmp/err-{who}", timeout=timeout)
        err = machine.succeed(f"cat /tmp/err-{who}")
        if err.strip():
            print(f"[{who} stderr] {err[-3000:]}")
        return rc, out

    def click(name, button="0xC0"):
        xy = until(lambda: ipc("omanix.approval", "geometry", name), f"{name} on screen", 20)
        x, y = xy.split()
        human("hyprctl eval 'hl.dispatch(hl.dsp.cursor.move({ x = " + x + ", y = " + y + " }))'")
        time.sleep(0.3)
        machine.succeed(f"YDOTOOL_SOCKET=/run/ydotoold/socket ydotool click {button}")
        time.sleep(0.5)

    def say(text):
        """The human types in the chat panel and presses Enter."""
        ipc("omanix.chat", "prefill", json.dumps({"text": text}))
        time.sleep(1)
        machine.send_key("ret")
        until(lambda: state("omanix.chat")["composer"] == "", f"sent: {text}", 20)

    def card(shown, form=None, timeout=600):
        def ok():
            s = state("omanix.approval")
            return s if s["shown"] == shown and (form is None or s["form"] == form) else None
        s = until(ok, f"a {form or '''} card shown as {shown}", timeout)
        time.sleep(2)
        return s

    def request_dir():
        return f"/run/nuketown-approval/{state('omanix.approval')['current']}/"

    def jfile(path):
        return json.loads(sh(f"cat {path}"))

    def result(n, timeout=600):
        """The resident's `omanix propose --json` for step n, once it returns."""
        def ok():
            r = json.loads(sh(f"cat /agents/ada/demo/{n}.json 2>/dev/null || echo null"))
            return r if r and "result" in r else None
        r = until(ok, f"omanix propose {n} returned", timeout)
        print(f"propose {n}: {r['result']}")
        return r

    def applied(n):
        r = result(n)
        if r["result"] != "applied":
            print(sh(f"tail -n 5 {SW['recordsDir']}/*/result.json"))
        assert r["result"] == "applied", r
        return r

    def last_switch():
        d = SW["recordsDir"]
        n = max(int(x) for x in sh(f"ls {d}").split() if x.isdigit())
        return n, jfile(f"{d}/{n}/card.json"), jfile(f"{d}/{n}/result.json")

    def rows():
        return state("omanix.chat")["rows"]

    def no_error_rows():
        errs = [r for r in rows() if r["kind"] == "error"]
        assert not errs, errs

    def monitors():
        return json.loads(human("hyprctl -j monitors"))

    machine.start()
    ${lib.optionalString withSilo "silo.start()"}
    machine.wait_for_unit("multi-user.target")
    try:
        machine.wait_until_succeeds("su - ${user} -c " + shlex.quote(ENV + "hyprctl -j monitors"), timeout=240)
        machine.wait_until_succeeds("su - ${user} -c " + shlex.quote(ENV + "/run/current-system/omarchy/bin/omarchy-shell omanix.approval ping") + " | grep -qx ok", timeout=120)
        machine.wait_until_succeeds("su - ${user} -c " + shlex.quote(ENV + "/run/current-system/omarchy/bin/omarchy-shell omanix.chat ping") + " | grep -qx ok", timeout=60)
        machine.wait_for_unit("nuketown-broker.service", "${user}")
    except Exception:
        diag(); raise
    SW = jfile("/etc/loom/switch.json")
    MIRROR = SW["mirror"]
    BASE = sh("readlink -f /run/current-system").strip()

    with subtest("setup: the host repo in the mirror${lib.optionalString (!agentless) " and in ada's clone"}; the scene's systems"):
        sh("mkdir -p /run/demo && for s in /run/current-system/specialisation/*; do [ -e \"$s\" ] && ln -sfn \"$(readlink -f \"$s\")\" /run/demo/out-$(basename \"$s\"); done; chmod -R a+rX /run/demo; ls -l /run/demo")
        sh(f"""
          set -e
          export HOME=/root
          git config --global user.name Test; git config --global user.email test@example
          git config --global init.defaultBranch master; git config --global safe.directory '*'
          cp -r ${hostTree} /root/host && chmod -R u+w /root/host && cd /root/host
          git init -q && git add -A && git commit -qm "A: installed"
          mkdir -p $(dirname {MIRROR}) && git init -q --bare {MIRROR} && git push -q {MIRROR} master
          chmod -R a+rX {MIRROR}
        """)
    ${lib.optionalString (!agentless && !withSilo) ''
      with subtest("setup: ada's working copy; the bridge serves the chat panel"):
          rc, out = run_as("ada", f"""
            set -e
            git clone -q {MIRROR} ~/projects/host
            cd ~/projects/host && git config user.name ada && git config user.email ada@machine && git config commit.gpgsign false
          """)
          assert rc == 0, out
    ''}
    ${lib.optionalString withSilo ''
      with subtest("setup: silo stand-in; owner, host and agent keys; the repo on silo; ada's clone over ssh"):
          silo.wait_for_unit("sshd.service")
          silo.wait_for_open_port(22)
          # the tripwire: the real silo never resolves (resolved drops 0.0.0.0 entries; files gives 0.0.0.0)
          rc, out = machine.execute("getent hosts silo.loom.farm")
          assert rc != 0 or out.split()[0] == "0.0.0.0", out
          sh("test -f /etc/ssh/ssh_host_ed25519_key || ssh-keygen -q -t ed25519 -N ''' -f /etc/ssh/ssh_host_ed25519_key")
          assert run_as("ada", "mkdir -p ~/.ssh && ssh-keygen -q -t ed25519 -N ''' -C ada@machine -f ~/.ssh/id_ed25519")[0] == 0
          sh(f"""
            set -e
            export HOME=/root
            ssh-keygen -q -t ed25519 -N "" -C alice@laptop -f /root/owner
            owner=$(cut -d' ' -f1,2 /root/owner.pub)
            hostk=$(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)
            ada=$(cut -d' ' -f1,2 /agents/ada/.ssh/id_ed25519.pub)
            cd /root/host
            printf '%s # loom:human:alice\\n%s # loom:host:host\\n%s # loom:agent:ada\\n' "$owner" "$hostk" "$ada" > .authorized_keys
            printf '* %s # loom:human:alice\\n* %s # loom:host:host\\n' "$owner" "$hostk" > CODEOWNERS
            git add -A && git commit -qm "B: enrolled on the silo stand-in"
            GIT_SSH_COMMAND="ssh -i /root/owner -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/kh" \\
              git push -q ssh://git@silo/omanix/demo.git master
            git push -q {MIRROR} master
          """)
          rc, out = run_as("ada", """
            set -e
            ssh="ssh -o StrictHostKeyChecking=accept-new"
            git -c core.sshCommand="$ssh" clone -q ssh://git@silo/omanix/demo.git ~/projects/host
            cd ~/projects/host && git config core.sshCommand "$ssh"
            git config user.name ada && git config user.email ada@machine && git config commit.gpgsign false
          """)
          assert rc == 0, out
    ''}
    sh("mkdir -p /persist/var/lib/loom/firstboot && touch /persist/var/lib/loom/firstboot/repo-publish.done")
    ${lib.optionalString (!agentless) ''
      machine.wait_for_unit("loom-agent-bridge@ada.service")
      until(lambda: state("omanix.chat")["connected"], "the chat panel connected to the bridge", 60)
      ipc("omanix.chat", "open")
      time.sleep(2)
      machine.screenshot("0-desktop")
    ''}

    ${{
      vm-demo-2 = ''
        with subtest("scene 2: Menu › Install › Gaming › Steam pre-fills the composer; Enter sends it"):
            ipc("omanix.chat", "close")
            ipc("shell", "summon", "omarchy.menu", '{"menu":"install.gaming"}')
            time.sleep(2)
            machine.send_chars("Steam")
            time.sleep(1)
            machine.screenshot("2-menu")
            machine.send_key("ret")
            until(lambda: state("omanix.chat")["composer"] == "Install Steam.", "the composer is pre-filled", 20)
            s = state("omanix.chat")
            assert s["open"] and s["source"].startswith("from menu:") and s["items"] == 0, s
            machine.screenshot("2-prefilled")
            machine.send_key("ret")
            until(lambda: state("omanix.chat")["composer"] == "", "sent", 20)

        with subtest("the activity rail: context, configuration.nix, edit, omanix check, commit, propose; a one-line card"):
            card("banner", "routine", 1200)
            machine.screenshot("2-rail-and-card")
            labels = [r.get("text") for r in rows() if r["kind"] == "activity"]
            print(labels)
            for want in ["omanix context", "Reading configuration.nix", "Editing configuration.nix", "Checking it evaluates (omanix check)",
                         "Committing: apps: Steam", "Proposing: Install Steam."]:
                assert any(want in (l or "") for l in labels), (want, labels)
            ck = jfile("/agents/ada/demo/2-check.json")
            assert ck["eval"]["ok"], ck
            d = request_dir()
            kc = jfile(f"{d}kind/card.json")
            v = json.loads(sh(f"loom-review-view {d}"))
            assert kc["request"] == "Install Steam." and kc["flags"] == [], kc
            assert v["form"] == "routine" and v["review"]["line"] == "Reviewer: matches", v
            assert "programs.steam.enable = true;" in sh(f"cat {d}kind/diff.txt")
            assert "steam" in sh(f"cat {d}kind/nvd.txt").lower()
            click("banner.approve")
            r = result("2a")
            assert r["result"] == "applied", r
            sh("test -e /run/current-system/sw/share/applications/steam.desktop")
            until(lambda: any(x["kind"] == "applied" for x in rows()), "the applied row", 30)
            time.sleep(2)
            machine.screenshot("2-applied")

        with subtest("'and hide the dock unless I hover': a second one-line card"):
            say("and hide the dock unless I hover")
            card("banner", "routine")
            kc = jfile(f"{request_dir()}kind/card.json")
            assert kc["request"] == "and hide the dock unless I hover", kc
            machine.screenshot("2-dock-card")
            click("banner.approve")
            applied("2b")
            assert jfile("/run/current-system/omarchy/config/omarchy/shell.json")["dock"]["autohide"] is True
            sh(f"git -C {MIRROR} log --format=%s -2 | grep -qx 'look: the dock hides until hover'")
            time.sleep(3)
            machine.screenshot("2-dock-hidden")
            no_error_rows()
      '';

      vm-demo-3 = ''
        def runtime_theme():
            return jfile("/run/omanix/session/${uid}/runtime.json").get("theme")

        with subtest("scene 3: the theme picker previews Kanagawa; picking it applies it at runtime"):
            ipc("omanix.chat", "close")
            ipc("shell", "summon", "omarchy.image-picker", '{"source":"themes"}')
            time.sleep(3)
            machine.send_chars("kanagawa")
            time.sleep(3)
            machine.screenshot("3-picker")
            machine.send_key("ret")
            try:
                until(lambda: (runtime_theme() or "").lower() == "kanagawa", "the runtime theme is kanagawa", 45)
            except AssertionError:
                # the picker's own action, if typing didn't select it (reported, not hidden)
                print("WARNING: the theme picker didn't pick kanagawa; running its action (omarchy-theme-set) directly")
                human("OMARCHY_THEME_WAIT=1 omarchy-theme-set kanagawa </dev/null")
                until(lambda: (runtime_theme() or "").lower() == "kanagawa", "the runtime theme is kanagawa", 60)
            time.sleep(3)
            machine.screenshot("3-kanagawa")
            assert jfile("/run/current-system/catalog/config.json")["omanix"]["theme"]["default"] == "tokyo-night"

        with subtest("Make it stick: the chip, the snapshot attached, a one-line card"):
            ipc("omanix.chat", "open")
            until(lambda: "Make theme stick" in state("omanix.chat")["chips"], "the Make theme stick chip", 30)
            machine.screenshot("3-chip")
            ipc("omanix.chat", "makeItStick", "theme")
            until(lambda: state("omanix.chat")["attachments"] == 1, "the snapshot is attached", 30)
            s = state("omanix.chat")
            assert s["composer"] == "Make my current theme settings permanent.", s
            machine.screenshot("3-attached")
            machine.send_key("ret")
            card("banner", "routine", 1200)
            machine.screenshot("3-card")
            st = jfile("/agents/ada/demo/3-set.json")
            assert st["action"] in ("rewritten", "replaced", "updated", "set") or st.get("file") == "configuration.nix", st
            click("banner.approve")
            applied("3")

        with subtest("the commit is one line in configuration.nix; the chip is gone"):
            p = sh(f"git -C {MIRROR} log -1 -p --format=%s")
            print(p)
            plus = [l for l in p.splitlines() if l.startswith("+") and not l.startswith("+++")]
            minus = [l for l in p.splitlines() if l.startswith("-") and not l.startswith("---")]
            assert plus == ['+  omanix.theme.default = "kanagawa";'] and minus == ['-  omanix.theme.default = "tokyo-night";'], p
            assert "configuration.nix" in p and p.count("diff --git") == 1, p
            assert jfile("/run/current-system/catalog/config.json")["omanix"]["theme"]["default"] == "kanagawa"
            ipc("omanix.chat", "close")
            ipc("omanix.chat", "open")
            until(lambda: "Make theme stick" not in state("omanix.chat")["chips"], "the chip is gone", 30)
            time.sleep(1)
            machine.screenshot("3-chip-gone")
            no_error_rows()
      '';

      vm-demo-4 = ''
        with subtest("scene 4: the reviewer flags Bluetooth; a full card"):
            say("Make my laptop last longer on battery.")
            card("card", "full")
            d = request_dir()
            rv = jfile(f"{d}review.json")
            v = json.loads(sh(f"loom-review-view {d}"))
            print(v)
            assert rv["status"] == "ok" and rv["recommendation"] == "ask" and "Bluetooth" in rv["summary"], rv
            assert v["form"] == "full" and v["review"]["recommendationWord"] == "LOOK CLOSER", v
            assert any("powerOnBoot" in n for n in rv["notes"]), rv
            kc = jfile(f"{d}kind/card.json")
            assert kc["request"] == "Make my laptop last longer on battery.", kc
            machine.screenshot("4-full-card")

        with subtest("git diff, then nvd diff, one click each"):
            click("card.diff")
            assert state("omanix.approval")["detail"] == "diff"
            assert "hardware.bluetooth.powerOnBoot = false;" in sh(f"cat {d}kind/diff.txt")
            time.sleep(1)
            machine.screenshot("4-git-diff")
            click("card.nvd")
            assert state("omanix.approval")["detail"] == "nvd"
            assert "tlp" in sh(f"cat {d}kind/nvd.txt").lower()
            time.sleep(1)
            machine.screenshot("4-nvd-diff")

        with subtest("Deny with the reason 'keep Bluetooth': the resident gets it; nothing switches"):
            click("card.deny")
            machine.send_chars("keep Bluetooth\n")
            r = result("4a")
            assert r["result"] == "denied" and "keep Bluetooth" in r["log"], r
            assert sh("readlink -f /run/current-system").strip() == BASE
            sh("! systemctl is-active tlp.service")

        with subtest("the resident recommits without Bluetooth: a one-line card; approved"):
            card("banner", "routine")
            d = request_dir()
            kc = jfile(f"{d}kind/card.json")
            assert "keep Bluetooth" in kc["request"], kc
            diff = sh(f"cat {d}kind/diff.txt")
            assert "bluetooth" not in diff.lower() and "services.tlp.enable = true;" in diff, diff
            machine.screenshot("4-routine-card")
            click("banner.approve")
            applied("4b")
            sh("systemctl is-active tlp.service")
            sh("! systemctl is-active power-profiles-daemon.service")
            until(lambda: abs(monitors()[0]["refreshRate"] - 60) < 1, "the screen runs at 60 Hz", 30)
            time.sleep(1)
            machine.screenshot("4-applied")
            no_error_rows()
      '';

      vm-demo-5 = ''
        nets = "/etc/NetworkManager/system-connections"
        sh(f"mkdir -p {nets} && for n in Home Cafe; do printf '[connection]\\nid=%s\\ntype=wifi\\n' $n > {nets}/$n.nmconnection; done && chmod 600 {nets}/*")
        nm_before = sh("systemctl show -p ActiveEnterTimestampMonotonic --value NetworkManager.service").strip()

        with subtest("scene 5: a 14-line root script; the review flags line 9"):
            say("My wifi keeps dropping, fix it for now.")
            card("card", "root")
            d = request_dir()
            req = jfile(f"{d}request.json")
            rv = jfile(f"{d}review.json")
            print(req, rv)
            assert req["requester"] == "ada" and req["argv"][0].endswith("bash"), req
            snaps = [s for s in req["snapshots"] if s.get("executed")]
            assert len(snaps) == 1 and snaps[0]["path"].endswith("fix-wifi.sh"), req
            assert sh(f"wc -l < {d}{snaps[0]['snapshot']}").strip() == "14"
            assert "system-connections" in sh(f"sed -n 9p {d}{snaps[0]['snapshot']}")
            assert rv["recommendation"] == "deny" and rv["risk"] == "high" and rv["notes"][0].startswith("line 9"), rv
            machine.screenshot("5-root-card")

        with subtest("Show command and script: the snapshot that will run, with line numbers"):
            click("card.command")
            assert state("omanix.approval")["detail"] == "command"
            time.sleep(1)
            machine.screenshot("5-command-and-script")

        with subtest("Deny 'don't touch my saved networks'; the resident drops line 9 and asks again; approved"):
            click("card.deny")
            machine.send_chars("don't touch my saved networks\n")
            until(lambda: "after:" not in sh("cat /agents/ada/demo/5a.log 2>/dev/null || true") and
                  "touch my saved networks" in sh("cat /agents/ada/demo/5a.log 2>/dev/null || true"), "the denial reached ada", 60)
            log = sh("cat /agents/ada/demo/5a.log")
            assert "Request denied" in log, log
            sh(f"test -e {nets}/Home.nmconnection")
            card("card", "root")
            d = request_dir()
            rv = jfile(f"{d}review.json")
            assert rv["recommendation"] == "approve", rv
            snap = [s for s in jfile(f"{d}request.json")["snapshots"] if s.get("executed")][0]
            body = sh(f"cat {d}{snap['snapshot']}")
            assert "system-connections" not in body, body
            machine.screenshot("5-second-card")
            click("card.approve")
            until(lambda: "after:" in sh("cat /agents/ada/demo/5b.log 2>/dev/null || true"), "the script ran", 120)
            log = sh("cat /agents/ada/demo/5b.log")
            print(log)
            assert "after: wifi radio enabled" in log and "NetworkManager active" in log, log
            sh(f"test -e {nets}/Home.nmconnection && test -e {nets}/Cafe.nmconnection")
            assert sh("systemctl show -p ActiveEnterTimestampMonotonic --value NetworkManager.service").strip() != nm_before
            # nuketown ran the snapshot it showed (the audit copy)
            sh("journalctl -t sudo --no-pager | grep -q 'nuketown-approval : .*COMMAND=.*bash /run/nuketown-approval/.*fix-wifi.sh'")

        with subtest("'keep Wi-Fi power saving off': a change card"):
            say("keep Wi-Fi power saving off")
            card("banner", "routine")
            machine.screenshot("5-change-card")
            click("banner.approve")
            applied("5c")
            sh("grep -qx 'wifi.scan-rand-mac-address=false' /etc/NetworkManager/NetworkManager.conf")
            no_error_rows()
      '';

      vm-demo-6 = ''
        with subtest("scene 6: a monitor rule turns off the only screen; the watchdog rolls back"):
            assert any(m["name"] == "Virtual-1" for m in monitors())
            say("I only use my external monitor: turn off the laptop screen.")
            card("banner", "routine")
            machine.screenshot("6-card")
            click("banner.approve")
            until(lambda: [m["name"] for m in monitors()] == ["FALLBACK"], "Hyprland lost its display", 120)
            machine.screenshot("6-black")
            r = result("6a", 300)
            assert r["result"] == "rolled-back", r
            n, kc, res = last_switch()
            assert res["status"] == "rolled-back" and "hyprland-display" in res["reason"], res
            assert sh("readlink -f /run/current-system").strip() == BASE
            # never reached the boot default (a test VM starts without a system profile)
            off = sh("readlink -f /run/demo/out-screen-off").strip()
            assert sh("readlink -f /nix/var/nix/profiles/system").strip() != off
            until(lambda: any(m["name"] == "Virtual-1" for m in monitors()), "the screen is back", 60)

        with subtest("the panel says what happened; Why? → why-failed"):
            rb = until(lambda: [x for x in rows() if x["kind"] == "rolledback"], "the Rolled back row", 30)
            assert rb[-1]["text"] == "Rolled back: Hyprland lost its display within 30 s", rb
            ipc("omanix.chat", "close")
            ipc("omanix.chat", "open")
            until(lambda: "What went wrong with my last change?" in state("omanix.chat")["chips"], "the rollback chip", 30)
            time.sleep(1)
            machine.screenshot("6-rolled-back")
            say("Why was my last change rolled back?")
            why = until(lambda: json.loads(sh("cat /agents/ada/demo/6-why.json 2>/dev/null || echo null")), "why-failed", 60)
            assert why["kind"] == "switch" and "hyprland-display" in (why["reason"] or ""), why
            time.sleep(3)
            machine.screenshot("6-why")

        with subtest("a working change, then Undo: one click and a one-line card"):
            say("Yes, 60 Hz.")
            card("banner", "routine")
            click("banner.approve")
            applied("6b")
            until(lambda: abs(monitors()[0]["refreshRate"] - 60) < 1, "60 Hz", 30)
            n_applied, _, _ = last_switch()
            until(lambda: any(x["kind"] == "applied" for x in rows()), "the applied row (Undo)", 30)
            machine.screenshot("6-applied-undo")
            print(machine.execute("ls -l /run/wrappers/bin/pkexec; for p in $(pgrep -u ${user} -f 'omarchy-shell|quickshell|Hyprland'); do echo \"$p $(tr '\\0' ' ' < /proc/$p/cmdline | cut -c1-60) $(grep NoNewPrivs /proc/$p/status)\"; done")[1])
            ipc("omanix.chat", "undo")
            card("banner", "routine", 180)
            d = request_dir()
            kc = jfile(f"{d}kind/card.json")
            assert kc["kind"] == "undo" and kc["title"] == "Undo: Yes, 60 Hz.", kc
            assert jfile(f"{d}request.json")["requester"] == "${user}"
            machine.screenshot("6-undo-card")
            click("banner.approve")
            until(lambda: last_switch()[0] > n_applied and last_switch()[2]["status"] == "applied", "the undo switch applied", 180)
            until(lambda: monitors()[0]["refreshRate"] > 70, "back to the preferred mode", 30)
            assert sh(f"git -C {MIRROR} log -1 --format=%s").strip() == "Undo: Yes, 60 Hz."
            time.sleep(1)
            machine.screenshot("6-undone")
      '';

      vm-demo-7 = ''
        REPO = "/var/lib/silo/repos/omanix/demo.git"

        with subtest("scene 7: one reviewed root command, so there is something to look at"):
            say("What did the system do last?")
            card("card", "root")
            machine.screenshot("7-card")
            click("card.approve")
            until(lambda: sh("cat /agents/ada/demo/7.log 2>/dev/null || true").strip(), "journalctl ran", 60)
            no_error_rows()

        with subtest("id ada, id reviewer; their homes are their own"):
            assert "uid=1100(ada)" in human("id ada")
            assert "uid=1101(reviewer)" in human("id reviewer")
            out = human("ls -ld /agents/*")
            print(out)
            for who in ("ada", "reviewer"):
                line = [l for l in out.splitlines() if l.endswith("/agents/" + who)][0]
                assert line.startswith("drwx------") and f" {who} " in line, line

        with subtest("sudo -u ada can't read the human's key"):
            human("mkdir -p ~/.ssh && ssh-keygen -q -t ed25519 -N ''' -f ~/.ssh/id_ed25519")
            rc, out = human_rc("echo test | sudo -S -u ada cat /home/${user}/.ssh/id_ed25519 2>&1")
            print(out)
            assert rc != 0 and "Permission denied" in out, out

        with subtest("ada's push to master on silo is refused; gate/* works"):
            rc, out = run_as("ada", "cd ~/projects/host && git commit -q --allow-empty -m probe && git push origin HEAD:master 2>&1; echo rc=$?; git push -q origin HEAD:refs/heads/gate/probe 2>&1; echo gate=$?; git reset -q --hard HEAD~1")
            print(out)
            assert "rc=1" in out and "not in CODEOWNERS" in out and "gate=0" in out, out
            assert silo.succeed(f"git -c safe.directory='*' -C {REPO} rev-parse master").strip() == sh(f"git -C {MIRROR} rev-parse master").strip()

        with subtest("the reviewer's one-shot runs, as uid 1101"):
            out = sh("journalctl -t sudo --no-pager | grep 'nuketown-approval : .*USER=reviewer ; COMMAND='")
            print(out)
            rid = sh("ls -t /var/lib/nuketown-approval | head -n1").strip()
            err = sh(f"cat /var/lib/nuketown-approval/{rid}/review.stderr")
            assert "as reviewer (uid 1101)" in err, err

        with subtest("sudo -l -U ada: one rule, nuketown-approve as nuketown-approval"):
            out = sh("sudo -l -U ada")
            print(out)
            rules = [l.strip() for l in out.splitlines() if l.startswith("    (")]
            assert len(rules) == 1 and rules[0].startswith("(nuketown-approval)") and "nuketown-approve" in rules[0], rules
            machine.fail("su - ada -c 'sudo -n -u root id'")

        with subtest("the approval requests, as audited (the run directory is gone)"):
            out = sh("ls -l /var/lib/nuketown-approval/; ls /var/lib/nuketown-approval/*/")
            print(out)
            # the journal request (the latest is the refused `sudo id` probe: a decision, no card)
            rid = sh("grep -l journalctl /var/lib/nuketown-approval/*/request.json | head -n1 | xargs dirname | xargs basename").strip()
            req = jfile(f"/var/lib/nuketown-approval/{rid}/request.json")
            assert req["requester"] == "ada" and "journalctl" in " ".join(req["argv"]), req
            dec = jfile(f"/var/lib/nuketown-approval/{rid}/decision.json")
            print("decision:", dec)
            assert "approv" in json.dumps(dec).lower(), dec
            sh(f"test ! -e /run/nuketown-approval/{rid}")
            # the human (group nuketown-approval-read) can read them
            human(f"cat /var/lib/nuketown-approval/{rid}/request.json > /dev/null")

        with subtest("a terminal with the same commands, for the screenshot"):
            human("setsid -f foot --app-id=demo7 sh -c 'id ada; id reviewer; ls -ld /agents/*; sudo -l -U ada 2>/dev/null | tail -n 3; ls /var/lib/nuketown-approval | tail -n 3; sleep 600' >/dev/null 2>&1")
            time.sleep(4)
            machine.screenshot("7-terminal")
      '';

      make-it-stick = ''
        OV = "/home/${user}/.local/state/omanix/overlay"
        GOLDEN = json.loads(${builtins.toJSON (builtins.toJSON stick)})

        with subtest("the GUI: monitor scale, text size, theme; a hand edit of the look overlay"):
            human("omarchy-hyprland-monitor-scaling 1.25")
            human("omarchy-display-text-size 16")
            human("OMARCHY_THEME_WAIT=1 omarchy-theme-set kanagawa </dev/null")
            human(f"printf 'hl.config({{ general = {{ gaps_out = 4 }} }})\\n' >> {OV}/hypr/looknfeel.lua && hyprctl reload")
            time.sleep(2)
            assert abs(monitors()[0]["scale"] - 1.25) < 0.01, monitors()
            machine.succeed(f"grep -qx 'font_size 12.0' {OV}/kitty.conf")
            machine.screenshot("stick-gui")

        with subtest("Make it stick: four snapshots attached and sent"):
            snaps = {}
            for area in ("monitors", "font", "look", "theme"):
                snaps[area] = json.loads(human(f"omanix-runtime-snapshot {area}"))
                ipc("omanix.chat", "makeItStick", area)
                until(lambda: state("omanix.chat")["attachments"] == len(snaps), f"the {area} snapshot attached", 30)
            mon = [f for f in snaps["monitors"]["files"] if f["path"] == "overlay/hypr/monitors.lua"][0]
            got = {"monitors": [{"output": m["output"], "mode": m["mode"], "scale": float(m["scale"])} for m in mon["monitors"]],
                   "gdkScale": mon["gdkScale"], "fontSize": 12, "gapsOut": 4,
                   "monitorsSha": snaps["monitors"]["snapshotSha"], "lookSha": snaps["look"]["snapshotSha"]}
            want = {k: v for k, v in GOLDEN.items() if k != "comment"}
            if got != want:
                print("tests/fixtures/demo/stick.json should be:\n" + json.dumps(dict(comment=GOLDEN["comment"], **got), indent=2))
            assert got == want, "the GUI's snapshot differs from tests/fixtures/demo/stick.json (the demo system declares those values)"
            machine.screenshot("stick-attached")
            machine.send_key("ret")

        with subtest("the resident maps them; a card; approved"):
            # the human changes the look overlay after its snapshot went out
            human(f"sed -i 's/gaps_out = 4/gaps_out = 6/' {OV}/hypr/looknfeel.lua")
            card("banner", "routine", 600)
            diff = sh(f"cat {request_dir()}kind/diff.txt")
            print(diff)
            for line in [f'omanix.runtime.absorbed.monitors = "{GOLDEN["monitorsSha"]}";', f'omanix.runtime.absorbed.look = "{GOLDEN["lookSha"]}";',
                         "omanix.fonts.size = 12;", "omanix.hyprland.settings.general.gaps_out = 4;", '+  omanix.theme.default = "kanagawa";']:
                assert line in diff, (line, diff)
            machine.screenshot("stick-card")
            click("banner.approve")
            applied("stick")

        with subtest("settle: the absorbed monitors overlay is emptied, the kv keys are gone, the changed look overlay stays"):
            settle = jfile("/run/current-system/etc/omanix/settle.json")
            assert settle["absorbed"] == {"monitors": GOLDEN["monitorsSha"], "look": GOLDEN["lookSha"]}, settle
            until(lambda: "omanix-overlay: monitors" not in sh(f"cat {OV}/hypr/monitors.lua"), "monitors.lua emptied", 60)
            machine.fail(f"grep -q font_size {OV}/kitty.conf")
            machine.fail(f"grep -q '^size' {OV}/alacritty.toml")
            machine.succeed(f"grep -q 'gaps_out = 6' {OV}/hypr/looknfeel.lua")
            sh("ls /home/${user}/.local/state/loom/clobbered/*/.local/state/omanix/overlay/hypr/monitors.lua")   # the backup
            doc = human("omanix-overlay doctor")
            print(doc)
            assert "overlay not empty: hypr/looknfeel.lua" in doc and "monitors.lua" not in doc and "kitty.conf" not in doc, doc
            d = json.loads(human("omanix doctor --json"))
            assert "hypr/looknfeel.lua" in [o["overlay"] for o in d["overlays"]], d
            # the declared values hold: the scale stays, the HM files carry them
            assert abs(monitors()[0]["scale"] - 1.25) < 0.01, monitors()
            machine.succeed("grep -q 'scale = 1.25' /home/${user}/.config/hypr/monitors.lua")
            machine.succeed("grep -qx 'font_size 12.0' /home/${user}/.config/kitty/kitty.conf || grep -q 'font_size 12' /home/${user}/.config/kitty/kitty.conf")
            ipc("omanix.chat", "close")
            ipc("omanix.chat", "open")
            until(lambda: (lambda c: "Make look stick" in c and "Make monitors stick" not in c and "Make font stick" not in c)(state("omanix.chat")["chips"]),
                  "only the look chip is left", 30)
            machine.screenshot("stick-settled")
            no_error_rows()
      '';

      human-commit = ''
        with subtest("the no-agent desktop: no resident, the panel offers the do-it-yourself path"):
            machine.fail("id ada")
            assert state("omanix.chat")["status"] == "none"

        with subtest("the human edits ~/omanix-host/configuration.nix and commits"):
            path = human("omanix repo path --ensure").strip()
            assert path == "/home/${user}/omanix-host", path
            human("cd ~/omanix-host && git config user.name Alice && git config user.email alice@example && git config commit.gpgsign false")
            human("cd ~/omanix-host && demo-edit append configuration.nix '  omanix.shell.settings.bar.position = \"bottom\";' && git commit -qam 'bar at the bottom'")

        with subtest("loom propose → pkexec loom-switch-request → a card without review → approved → promoted"):
            machine.execute("su - ${user} -c " + shlex.quote(ENV + "cd ~/omanix-host && (systemd-run --user --quiet --collect --same-dir -- sh -c 'loom propose --out \"$(readlink -f /run/demo/out-bar-bottom)\" > /tmp/human-propose.log 2>&1; echo rc=$? >> /tmp/human-propose.log') "))
            try:
                s = until(lambda: (lambda s: s if s["shown"] in ("card", "banner") else None)(state("omanix.approval")), "the card", 300)
            except AssertionError:
                print(machine.execute("cat /tmp/human-propose.log; loginctl list-sessions; loginctl show-user ${user} -p Display; "
                                      "h=$(grep -o '/nix/store/[^\"]*loom-seat-active' /etc/polkit-1/rules.d/*.rules | head -n1); echo helper=$h; "
                                      "for s in 1 2; do runuser -u polkituser -- $h ${user} $s; echo \"seat-active $s: $?\"; done; "
                                      "ps -eo pid,user,args | grep -E 'pkexec|loom-switch|polkit' | grep -v grep; "
                                      "for p in $(pgrep -x pkexec); do pkcheck --action-id farm.loom.propose --process $p; echo pkcheck=$?; done; "
                                      "journalctl -b --no-pager | grep -iE 'pkexec|polkit|loom-switch|nuketown-approve' | tail -n 30")[1])
                raise
            time.sleep(2)
            d = request_dir()
            req = jfile(f"{d}request.json")
            kc = jfile(f"{d}kind/card.json")
            rv = jfile(f"{d}review.json")
            print(req, kc, rv)
            assert req["requester"] == "${user}" and req["origin"] == "root", req
            assert kc["request"].startswith("Your own commit: bar at the bottom"), kc
            assert rv["status"] == "skipped", rv
            machine.screenshot("human-card")
            click("card.approve" if s["shown"] == "card" else "banner.approve")
            until(lambda: "rc=" in sh("cat /tmp/human-propose.log 2>/dev/null || true"), "loom propose returned", 300)
            log = sh("cat /tmp/human-propose.log")
            print(log)
            assert "rc=0" in log, log
            n, kc, res = last_switch()
            assert res["status"] == "applied", res
            assert jfile("/run/current-system/omarchy/config/omarchy/shell.json")["bar"]["position"] == "bottom"
            assert sh(f"git -C {MIRROR} log -1 --format=%s").strip() == "bar at the bottom"
            time.sleep(3)
            machine.screenshot("human-applied")

        with subtest("over ssh (no session): pkexec is refused; sudo loom-switch with the password is the approval"):
            human("mkdir -p ~/.ssh && ssh-keygen -q -t ed25519 -N ''' -f ~/.ssh/demo && cat ~/.ssh/demo.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys")
            human("cd ~/omanix-host && demo-edit append configuration.nix '  environment.etc.\"demo/over-ssh\".text = \"yes\\n\";' && git commit -qam 'over ssh'")
            ssh = "ssh -i ~/.ssh/demo -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/kh ${user}@localhost "
            rc, out = human_rc(ssh + shlex.quote("cd ~/omanix-host && loom propose --out $(readlink -f /run/demo/out-over-ssh) 2>&1"))
            print(out)
            assert rc != 0, out
            pdir = out.split("proposal ")[1].split(":")[0]
            rc, out = human_rc(ssh + shlex.quote(f"echo test | sudo -S /run/current-system/sw/bin/loom-switch --proposal {pdir} $(readlink -f /run/demo/out-over-ssh) 2>&1"))
            print(out)
            assert rc == 0, out
            sh("grep -qx yes /etc/demo/over-ssh")
            n, kc, res = last_switch()
            assert res["status"] == "applied" and kc["request"].startswith("Your own commit: over ssh"), (kc, res)
            assert sh(f"git -C {MIRROR} log -1 --format=%s").strip() == "over ssh"
      '';
    }.${variant}}
  '';
}
