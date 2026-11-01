# W18's VM tests: the omanix shell plugins in the real session (Hyprland under
# uwsm, the fork's Quickshell shell, nuketown's broker, loom's chat bridge
# with the replay harness). One node, four variants:
#
#   chat-socket      U10: the panel connects to /run/loom/chat/ada.sock,
#                    talks loom.chat/v1, survives a bridge restart and
#                    reconnects to the new boot.
#   approval-card    omanix-approval-prompt (as nuketown's prompter) draws a
#                    root-command card and change cards from fixture request
#                    directories (screenshots); the broker answers APPROVED
#                    and DENIED:<reason>; the keys (Ctrl+I, Ctrl+C, Esc,
#                    Ctrl+Enter); with no shell it falls back to nuketown's
#                    card, where Esc Esc dismisses.
#   approval-focus   U13: a card over a fullscreen terminal takes the keyboard
#                    only on a click and gives it back (deciding, or Esc Esc
#                    dismissing); it stands aside while
#                    a pinentry window is up.
#   desktop-intents  a menu intent row pre-fills the chat composer and sends
#                    nothing until Enter (screenshot); the bar shows the
#                    approval and agent indicators; the clock's middle click
#                    opens the timezone row (P19).
{ pkgs, loom, omanix, variant }:

let
  inherit (pkgs) lib;
  template = loom.outPath + "/templates/host";
  user = "alice";
  uid = "1000";
  env = "XDG_RUNTIME_DIR=/run/user/${uid} OMARCHY_PATH=/run/current-system/omarchy";
  asUser = cmd: "su - ${user} -c ${lib.escapeShellArg "${env} ${cmd}"}";
  fixtures = ./fixtures/approval;

  replay = pkgs.writeText "w18.jsonl" ''
    {"on": "user"}
    {"text": "I'll **check** that. `nix` first."}
    {"emit": {"t": "activity", "kind": "read", "label": "Reading configuration.nix"}}
    {"emit": {"t": "question", "text": "Which one?", "choices": ["Steam", "Lutris"]}}
    {"on": "user"}
    {"text": "Done."}
  '';
in
pkgs.testers.runNixOSTest {
  name = "omanix-${variant}";
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom omanix; };

  nodes.machine = { config, lib, ... }: {
    imports = [
      loom.nixosModules.default
      (loom.lib.mkHostModule { self = template; homeModules = [ (template + "/home.nix") ]; hostInputs = { }; system = "x86_64-linux"; })
      omanix.nixosModules.default
      (template + "/configuration.nix")
      (loom.outPath + "/tests/vm/disk-standin.nix")
    ];

    networking.hostName = lib.mkForce "machine";
    users.users.${user}.password = "test";
    omanix.session.autologin = true;
    omanix.welcome.autoOpen = false;

    loom.agent.harness = lib.mkForce "replay";
    loom.chat.replay.script = replay;

    # Clicks for the tests (uinput); the human is not in the group.
    programs.ydotool.enable = true;
    environment.systemPackages = [ pkgs.socat pkgs.foot ];

    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
    virtualisation.diskSize = lib.mkForce 4096;
    virtualisation.qemu.options = [ "-vga none" "-device virtio-gpu-pci" ];
  };

  testScript = ''
    import json, shlex, time

    def ipc(*args):
        quoted = " ".join(shlex.quote(a) for a in args)
        return machine.succeed("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell " + quoted)).strip()

    def state(target):
        return json.loads(ipc(target, "state"))

    def hypr(lua):
        machine.succeed("su - ${user} -c " + json.dumps("${env} hyprctl -i 0 dispatch " + json.dumps(lua)))

    def click(name, button="0xC0"):
        xy = ""
        for _ in range(40):
            xy = ipc("omanix.approval", "geometry", name)
            if xy:
                break
            time.sleep(0.25)
        assert xy, f"{name} has no geometry"
        x, y = xy.split()
        machine.succeed("su - ${user} -c " + json.dumps("${env} hyprctl -i 0 eval 'hl.dispatch(hl.dsp.cursor.move({ x = " + x + ", y = " + y + " }))'"))
        time.sleep(0.3)
        machine.succeed(f"YDOTOOL_SOCKET=/run/ydotoold/socket ydotool click {button}")
        time.sleep(0.5)

    def diag():
        print(machine.execute("journalctl -b --no-pager -n 200 _UID=${uid} | grep -i 'qml\\|omanix\\|warn\\|error' | tail -80")[1])

    machine.wait_for_unit("multi-user.target")
    machine.wait_until_succeeds(${builtins.toJSON (asUser "hyprctl -i 0 -j monitors")}, timeout=180)
    try:
        machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval ping") + " | grep -qx ok", timeout=120)
        machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat ping") + " | grep -qx ok", timeout=60)
    except Exception:
        diag(); raise
    machine.sleep(3)

    def dump():
        print(machine.execute("id ${user}; ls -la /run/nuketown-approval /run/nuketown-approval/* /run/nuketown-broker 2>&1; head -c 300 /tmp/answer-* 2>&1; "
          + "ls -laR /run/user/${uid}/omanix-approval 2>&1; "
          + "su - ${user} -c " + shlex.quote("${env} systemctl --user status nuketown-broker --no-pager; ${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " 2>&1; "
          + "journalctl -b --no-pager _UID=${uid} | grep -i 'broker\\|prompt\\|approval\\|qml\\|omanix' | tail -60")[1])

    def no_plugin_errors():
        out = machine.execute("journalctl -b --no-pager _UID=${uid} | grep -i 'omanix' | grep -i 'error\\|failed\\|is not a type\\|not defined\\|cannot assign\\|unable'")[1]
        assert out.strip() == "", out

    ${{
      chat-socket = ''
        with subtest("the panel connects once the bridge serves the socket"):
            assert state("omanix.chat")["connected"] is False
            machine.succeed("su - ada -c 'git init -q ~/projects/host'")
            machine.succeed("mkdir -p /persist/var/lib/loom/firstboot && touch /persist/var/lib/loom/firstboot/repo-publish.done")
            machine.wait_for_unit("loom-agent-bridge@ada.service")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q '\"connected\":true'", timeout=30)
            s = state("omanix.chat")
            assert s["boot"] and s["status"] == "idle", s

        with subtest("a message goes out on Enter and the replay answers"):
            ipc("omanix.chat", "open")
            machine.sleep(2)
            machine.send_chars("make my battery last\n")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q '\"items\":[4-9]'", timeout=30)
            s = state("omanix.chat")
            assert s["composer"] == "", s
            machine.screenshot("chat")

        with subtest("U10: a bridge restart drops the socket; the panel reconnects to the new boot"):
            boot1 = state("omanix.chat")["boot"]
            machine.succeed("systemctl restart loom-agent-bridge@ada.service")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q '\"connected\":true'", timeout=30)
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + f" | grep -v -q '{boot1}'", timeout=30)
            s = state("omanix.chat")
            assert s["boot"] != boot1 and s["connected"], (s, boot1)
            # stopped: offline, and the status indicator says so
            machine.succeed("systemctl stop loom-agent-bridge@ada.service")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q '\"status\":\"offline\"'", timeout=30)
            machine.succeed("systemctl start loom-agent-bridge@ada.service")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q '\"connected\":true'", timeout=30)
        no_plugin_errors()
      '';

      approval-card = ''
        def fixture(name, rid):
            d = f"/run/nuketown-approval/{rid}"
            machine.succeed(f"mkdir -p /run/nuketown-approval && rm -rf {d} && cp -r ${fixtures}/{name} {d} && chown -R root:nuketown-approval-read {d} && chmod -R u+w,g+rX,o-rwx {d} && chmod 2750 {d}")
            return d

        def request(rid):
            machine.succeed(f"(printf 'REQUEST:{rid}\\n\\n' | socat STDIO,ignoreeof UNIX-CONNECT:/run/nuketown-broker/socket > /tmp/answer-{rid}) >/dev/null 2>&1 &")

        def answer(rid):
            machine.wait_until_succeeds(f"test -s /tmp/answer-{rid}", timeout=30)
            return machine.succeed(f"cat /tmp/answer-{rid}").strip()

        machine.wait_until_succeeds("test -S /run/nuketown-broker/socket", timeout=60)

        with subtest("root-command card: drawn, then Approve -> APPROVED"):
            fixture("root-command", "w18-root")
            request("w18-root")
            try:
                machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"shown\":\"card\"'", timeout=30)
            except Exception:
                dump(); raise
            s = state("omanix.approval")
            assert s["form"] == "root" and s["engaged"] is False, s
            machine.sleep(2)
            assert s["review"] == "ok" and s["headline"].startswith("Restarts Wi-Fi, but line 9"), s
            machine.screenshot("card-root-command")
            click("card.info")
            assert state("omanix.approval")["detail"] == "info"
            machine.sleep(1)
            machine.screenshot("card-root-command-script")
            click("card.approve")
            assert answer("w18-root") == "APPROVED"

        with subtest("keys: Ctrl+I toggles details, Ctrl+C copies, Esc opens the reason, Ctrl+Enter approves"):
            fixture("root-command", "w18-keys")
            request("w18-keys")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"armed\":true'", timeout=30)
            s = state("omanix.approval")
            assert s["badge"]["contrast"] >= 4.5, s["badge"]
            click("card.requestText")     # into the card: it takes the keyboard
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"engaged\":true'", timeout=10)
            machine.send_key("ctrl-i")
            machine.sleep(1)
            assert state("omanix.approval")["detail"] == "info", state("omanix.approval")
            machine.send_key("ctrl-i")
            machine.sleep(1)
            assert state("omanix.approval")["detail"] == "", state("omanix.approval")
            machine.send_key("ctrl-a")
            machine.send_key("ctrl-c")
            machine.sleep(1)
            copied = machine.succeed("su - ${user} -c " + json.dumps("${env} WAYLAND_DISPLAY=$(basename $(ls /run/user/${uid}/wayland-? | head -1)) wl-paste -n"))
            assert "wifi keeps dropping" in copied, copied
            machine.send_key("esc")
            machine.sleep(1)
            s = state("omanix.approval")
            assert s["denyOpen"] is True and s["current"] == "w18-keys", s
            machine.send_key("ctrl-ret")
            assert answer("w18-keys") == "APPROVED", answer("w18-keys")

        with subtest("the review lands while the card is open: updated in place, the reason being typed kept"):
            d = fixture("root-pending", "w18-pending")
            request("w18-pending")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"review\":\"pending\"'", timeout=30)
            machine.sleep(2)
            machine.screenshot("card-root-pending")
            click("card.deny")
            machine.send_chars("not while")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"reason\":\"not while\"'", timeout=10)
            # nuketown replaces review.json atomically
            machine.succeed(f"cp ${fixtures}/root-command/review.json {d}/review.json.tmp && chgrp nuketown-approval-read {d}/review.json.tmp && chmod 640 {d}/review.json.tmp && mv -f {d}/review.json.tmp {d}/review.json")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"review\":\"ok\"'", timeout=10)
            s = state("omanix.approval")
            assert s["denyOpen"] is True and s["reason"] == "not while" and s["current"] == "w18-pending", s
            machine.sleep(1)
            machine.screenshot("card-root-reviewed-in-place")
            machine.send_chars(" I'm on a call\n")
            assert answer("w18-pending") == "DENIED:not while I'm on a call", answer("w18-pending")

        with subtest("full change card: Deny, a reason in the card -> DENIED:<reason>"):
            fixture("full", "w18-full")
            request("w18-full")
            try:
                machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"form\":\"full\"'", timeout=30)
            except Exception:
                dump(); raise
            machine.sleep(2)
            machine.screenshot("card-full")
            click("card.info")
            machine.sleep(1)
            machine.screenshot("card-full-info")
            click("card.diff")
            machine.sleep(1)
            machine.screenshot("card-full-diff")
            click("card.deny")
            machine.send_chars("keep bluetooth\n")
            assert answer("w18-full") == "DENIED:keep bluetooth", answer("w18-full")

        with subtest("routine change card: a one-line banner, Approve -> APPROVED"):
            fixture("routine", "w18-routine")
            request("w18-routine")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"shown\":\"banner\"'", timeout=30)
            machine.sleep(2)
            machine.screenshot("card-routine")
            click("banner.approve")
            assert answer("w18-routine") == "APPROVED"

        with subtest("no shell: the prompter falls back to nuketown's card (Wayland); Esc Esc dismisses"):
            # omarchy-launch-shell relaunches a shell that exits: stop it first.
            machine.succeed("pkill -u ${user} -f omarchy-launch-shell || true")
            machine.succeed("pkill -u ${user} -f 'quickshell .*-p /run/current-system/omarchy/shell' || true")
            machine.wait_until_fails("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval ping"), timeout=30)
            fixture("root-command", "w18-fallback")
            request("w18-fallback")
            try:
                machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} hyprctl -i 0 -j clients") + " | grep -q nuketown-prompter", timeout=30)
            except Exception:
                print(machine.execute("cat /tmp/answer-w18-fallback; ps -u ${user} -o pid,args | grep -i 'prompt'")[1]); dump(); raise
            machine.sleep(2)    # past the card's typing guard
            machine.screenshot("fallback-card")
            machine.send_key("esc")
            machine.sleep(1)
            machine.send_key("esc")
            assert answer("w18-fallback") == "DENIED:aborted by the human (dismissed without a reason)", answer("w18-fallback")
      '';

      approval-focus = ''
        def fixture(name, rid):
            d = f"/run/nuketown-approval/{rid}"
            machine.succeed(f"mkdir -p /run/nuketown-approval && rm -rf {d} && cp -r ${fixtures}/{name} {d} && chown -R root:nuketown-approval-read {d} && chmod -R u+w,g+rX,o-rwx {d} && chmod 2750 {d}")

        def request(rid):
            machine.succeed(f"(printf 'REQUEST:{rid}\\n\\n' | socat STDIO,ignoreeof UNIX-CONNECT:/run/nuketown-broker/socket > /tmp/answer-{rid}) >/dev/null 2>&1 &")

        def typed():
            return machine.succeed("cat /tmp/typed 2>/dev/null || true")

        machine.wait_until_succeeds("test -S /run/nuketown-broker/socket", timeout=60)

        with subtest("a fullscreen terminal has the keyboard"):
            machine.succeed("su - ${user} -c " + json.dumps("${env} WAYLAND_DISPLAY=$(basename $(ls /run/user/${uid}/wayland-? | head -1)) setsid foot --app-id=typetest sh -c 'cat > /tmp/typed' >/dev/null 2>&1 &"))
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} hyprctl -i 0 -j activewindow") + " | grep -q typetest", timeout=30)
            hypr('hl.dsp.window.fullscreen({ mode = "fullscreen" })')
            machine.sleep(1)
            machine.send_chars("one\n")
            machine.wait_until_succeeds("grep -qx one /tmp/typed", timeout=10)

        with subtest("U13: the card comes up over it without taking the keyboard"):
            fixture("root-command", "w18-focus")
            request("w18-focus")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"shown\":\"card\"'", timeout=30)
            machine.sleep(2)
            machine.screenshot("focus-card-over-fullscreen")
            machine.send_chars("two\n")
            machine.wait_until_succeeds("grep -qx two /tmp/typed", timeout=10)
            assert state("omanix.approval")["engaged"] is False

        with subtest("a click into the card gives it the keyboard; deciding gives it back"):
            click("card.deny")
            print(state("omanix.approval"))
            assert state("omanix.approval")["engaged"] is True
            machine.send_chars("not now\n")
            try:
                machine.wait_until_succeeds("test -s /tmp/answer-w18-focus", timeout=20)
            except Exception:
                print(typed()); dump(); raise
            assert machine.succeed("cat /tmp/answer-w18-focus").strip() == "DENIED:not now"
            assert "not now" not in typed(), typed()
            machine.sleep(1)
            machine.send_chars("three\n")
            machine.wait_until_succeeds("grep -qx three /tmp/typed", timeout=10)

        with subtest("Esc opens the reason; Esc again dismisses and hands the keyboard back"):
            fixture("root-command", "w18-escape")
            request("w18-escape")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"armed\":true'", timeout=30)
            click("card.requestText")
            machine.sleep(1)
            assert state("omanix.approval")["engaged"] is True
            machine.send_key("esc")
            machine.sleep(1)
            assert state("omanix.approval")["denyOpen"] is True
            machine.send_key("esc")
            machine.wait_until_succeeds("test -s /tmp/answer-w18-escape", timeout=20)
            assert machine.succeed("cat /tmp/answer-w18-escape").strip() == "DENIED:aborted by the human (dismissed without a reason)"
            machine.sleep(1)
            machine.send_chars("four\n")
            machine.wait_until_succeeds("grep -qx four /tmp/typed", timeout=10)

        with subtest("a pinentry window keeps the card away until it closes"):
            machine.succeed("su - ${user} -c " + json.dumps("${env} WAYLAND_DISPLAY=$(basename $(ls /run/user/${uid}/wayland-? | head -1)) setsid foot --app-id=pinentry-qt sh -c 'cat > /tmp/pin' >/dev/null 2>&1 &"))
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} hyprctl -i 0 -j clients") + " | grep -q pinentry-qt", timeout=30)
            fixture("root-command", "w18-pin")
            request("w18-pin")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"pending\":1'", timeout=30)
            machine.sleep(2)
            s = state("omanix.approval")
            assert s["pinentry"] is True and s["shown"] == "none", s
            machine.send_chars("1234\n")
            machine.wait_until_succeeds("grep -qx 1234 /tmp/pin", timeout=10)
            machine.screenshot("focus-pinentry-first")
            machine.succeed("pkill -u ${user} -f 'app-id=pinentry-qt'")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.approval state") + " | grep -q '\"shown\":\"card\"'", timeout=30)
            click("card.approve")
            machine.wait_until_succeeds("grep -qx APPROVED /tmp/answer-w18-pin", timeout=20)
        no_plugin_errors()
      '';

      desktop-intents = ''
        with subtest("a menu intent row pre-fills the composer and sends nothing"):
            ipc("shell", "summon", "omarchy.menu", '{"menu":"install.gaming"}')
            machine.sleep(2)
            machine.screenshot("menu-gaming")
            machine.send_chars("Steam")
            machine.sleep(1)
            machine.send_key("ret")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q '\"open\":true'", timeout=20)
            s = state("omanix.chat")
            assert s["composer"] == "Install Steam.", s
            assert s["source"].startswith("from menu:") and "Steam" in s["source"], s
            assert s["items"] == 0, s
            machine.sleep(1)
            machine.screenshot("intent-prefilled")

        with subtest("Escape sends nothing"):
            machine.send_key("esc")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q '\"open\":false'", timeout=20)
            assert state("omanix.chat")["items"] == 0

        with subtest("the language picker ends in an intent (P11)"):
            ipc("shell", "summon", "omarchy.menu", '{"menu":"setup.language"}')
            machine.sleep(3)
            machine.send_chars("Deutsch")
            machine.sleep(1)
            machine.send_key("ret")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q 'Switch my language to Deutsch.'", timeout=20)
            ipc("omanix.chat", "close")

        with subtest("the bar shows the approval and agent indicators"):
            s = state("omanix.status")
            assert s["offline"] is True and s["visible"] is True, s
            machine.succeed("mkdir -p /run/nuketown-approval && rm -rf /run/nuketown-approval/w18-bar && cp -r ${fixtures}/root-command /run/nuketown-approval/w18-bar && chown -R root:nuketown-approval-read /run/nuketown-approval/w18-bar && chmod -R g+rX /run/nuketown-approval/w18-bar")
            machine.succeed("(printf 'REQUEST:w18-bar\\n\\n' | socat STDIO,ignoreeof UNIX-CONNECT:/run/nuketown-broker/socket > /tmp/answer-bar) >/dev/null 2>&1 &")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.status state") + " | grep -q '\"pending\":1'", timeout=30)
            machine.sleep(1)
            machine.screenshot("bar-indicators")

        with subtest("the clock's middle click opens the timezone row (P19)"):
            ipc("omanix.approval", "dismiss", "w18-bar")
            mon = json.loads(machine.succeed("su - ${user} -c " + json.dumps("${env} hyprctl -i 0 -j monitors")))[0]
            x, y = mon["width"] // 2, 12
            machine.succeed("su - ${user} -c " + json.dumps("${env} hyprctl -i 0 eval 'hl.dispatch(hl.dsp.cursor.move({ x = " + str(x) + ", y = " + str(y) + " }))'"))
            time.sleep(0.5)
            machine.succeed("YDOTOOL_SOCKET=/run/ydotoold/socket ydotool click 0xC2")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} hyprctl -i 0 -j layers") + " | grep -q omarchy-menu", timeout=20)
            machine.sleep(3)
            machine.screenshot("clock-timezone")
            machine.send_chars("Europe/Berlin")
            machine.sleep(1)
            machine.send_key("ret")
            machine.wait_until_succeeds("su - ${user} -c " + json.dumps("${env} /run/current-system/omarchy/bin/omarchy-shell omanix.chat state") + " | grep -q 'Set my timezone to Europe/Berlin.'", timeout=20)
        no_plugin_errors()
      '';
    }.${variant}}
  '';
}
