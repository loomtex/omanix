# W18's checks: the intent menu, the shell plugins (omanix.chat,
# omanix.approval, omanix.status, omanix.welcome), the approval card and the
# patches P5, P7, P8, P10-P14, P18, P19. `nix flake check` is the gate (§i).
{ pkgs, self, inputs }:

let
  inherit (pkgs) lib omanixFork;
  f = omanixFork.forkDir;
  upstreamMenu = "${omanixFork.src}/default/omarchy/omarchy-menu.jsonc";
  py = pkgs.python3.withPackages (ps: [ ps.bashlex ]);

  host = self.nixosConfigurations.ref-default;
  data = host.config.omanix.fork.data;

  # checks.menu-intents (§h.5.2 step 4), at the pin: every upstream entry has
  # a row, gui actions and kept guards call only shipped scripts, intent rows
  # have text and a known skill, templates use only {label} {value}
  # {selection}. Each refusal fixture must fail for the stated reason.
  mutate = pkgs.writeText "menu-intents-mutate.py" ''
    import re, sys
    src, case, out = sys.argv[1:4]
    t = open(src).read()
    if case == "missing-row":
        t = re.sub(r'\[entry\."about"\]\nkind = "gui"\n\n', "", t, count=1)
    elif case == "dropped-script":
        t = t.replace('[entry."about"]\nkind = "gui"\n', '[entry."about"]\nkind = "gui"\naction = "omarchy-pkg-install"\n', 1)
    elif case == "unknown-skill":
        t = t.replace('skill = "apps"', 'skill = "nope"', 1)
    elif case == "bad-template":
        t = t.replace('text = "Install {label}."', 'text = "Install {kind}."', 1)
    elif case == "empty-text":
        t = t.replace('text = "Install {label}."', 'text = " "', 1)
    elif case == "stale-row":
        t += '\n[entry."install.nothing"]\nkind = "drop"\nwhy = "x"\n'
    assert t != open(src).read(), case
    open(out, "w").write(t)
  '';
  refusals = [ "missing-row" "dropped-script" "unknown-skill" "bad-template" "empty-text" "stale-row" ];

  # The card goldens (§h.4): the plugin's own CardModel.js renders the fixture
  # request directories; the model and its text form must equal
  # tests/golden/cards/<name>.{json,txt} (regenerate: tests/golden/update-cards.sh).
  cardGolden = name: pkgs.runCommand "omanix-check-card-golden-${name}" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${../tests/cards/render.js} ${pkgs.omarchy-src}/shell/plugins/omanix-approval/CardModel.js \
      ${../tests/fixtures/approval}/${name} got
    diff -u ${../tests/golden/cards}/${name}.json got.json
    diff -u ${../tests/golden/cards}/${name}.txt got.txt
    cat got.txt
    touch $out
  '';

  vm = variant: import ../tests/shell-plugins.nix { inherit pkgs variant; inherit (inputs) loom; omanix = self; };
in
{
  # The chat's Markdown subset escapes the agent's text; chips follow the rules.
  chat-model = pkgs.runCommand "omanix-check-chat-model" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${../tests/cards/chat-model.js} ${pkgs.omarchy-src}/shell/plugins/omanix-chat/ChatModel.js ${../data/chips/rules.json}
    touch $out
  '';

  card-golden-routine = cardGolden "routine";
  card-golden-full = cardGolden "full";
  card-golden-root-command = cardGolden "root-command";
  card-golden-root-details = cardGolden "root-details";
  card-golden-root-pending = cardGolden "root-pending";
  card-golden-full-no-headline = cardGolden "full-no-headline";

  # VM tests (§i.2): U10, U13, the card and the intents on the desktop.
  chat-socket = vm "chat-socket";
  approval-card = vm "approval-card";
  approval-focus = vm "approval-focus";
  desktop-intents = vm "desktop-intents";

  menu-intents = pkgs.runCommand "omanix-check-menu-intents" { nativeBuildInputs = [ py ]; } ''
    check() { python3 -I ${f}/tools/menu.py check ${upstreamMenu} "$1" ${f}/menu-extra.jsonc ${data}/bin; }
    check ${f}/intents.toml
    ${lib.concatMapStrings (c: ''
      python3 -I ${mutate} ${f}/intents.toml ${c} bad.toml
      if check bad.toml > out.txt; then cat out.txt; echo "refusal fixture ${c} passed the check" >&2; exit 1; fi
      grep -q '^FAIL:' out.txt
      echo "refused (${c}): $(grep -m1 '^FAIL:' out.txt)"
    '') refusals}
    # The built menu: no intent row keeps an action; dropped rows are gone;
    # the omanix entries are in.
    python3 -I - ${data}/default/omarchy/omarchy-menu.jsonc ${data}/default/omanix/intents.json <<'EOF'
    import json, sys
    sys.path.insert(0, "${f}/tools")
    import jsonc
    m = json.loads(jsonc.drop_trailing_commas(jsonc.strip(open(sys.argv[1]).read())))
    t = json.load(open(sys.argv[2]))
    bad = [k for k, e in m.items() if e.get("intent") and e.get("action")]
    assert not bad, f"intent rows with an action: {bad}"
    for k in ("setup.security.passwordless-sudo", "setup.default.agent.claude", "learn.community"):
        assert k not in m, f"{k} should be dropped"
    for k in ("ask", "approvals", "undo", "learn.nixos", "appearance.make-it-stick"):
        assert k in m, f"{k} missing"
    assert m["install.gaming.steam"]["intent"] == "Install {label}." and "steam" not in m["install.gaming.steam"].get("action", "")
    assert m["update.timezone"]["provider"] == "timezones"
    assert t["setup.default.browser.firefox"]["skill"] == "defaults"
    keys = list(m)
    assert keys.index("ask") == keys.index("apps") + 1, "ask follows apps"
    print(f"built menu: {len(m)} entries, {sum(1 for e in m.values() if e.get('intent'))} intent rows")
    EOF
    touch $out
  '';
}
