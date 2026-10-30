# §i.2 installer-e2e-omanix: loom's installer-e2e with the omanix flavor
# and the configure engine, offline, asserting cacheMiss = [].
#
#   silo       seed's silo stand-in (silo.test, pinned test host key) with
#              DHCP/DNS for the installed machine; silo.loom.farm → 0.0.0.0
#   laptop     "the user's other computer": `configure mint` (the human test
#              key, passphrase-protected, makes the first push), `configure
#              check` against the stick's index (asserts cacheMiss = []),
#              `configure sidecar`, loom-flash onto a fake USB stick
#   installer  omanix.lib.installer.modules { test = true; image = false; }:
#              the live system with the reference closures and the per-host
#              build inputs in its store and NO substituter (offline). The
#              driver answers the line-mode TUI; there is no answers file.
#   target     the installed disk booted through OVMF
#
# The piece from loom's tests/lib/installer-common.nix that this needs (the
# silo node and the TUI helpers) is copied, not imported: that file exports
# only mkTest, which builds a loom-flavored installer node. The fixtures
# (throwaway keys, the fake signed release) are imported from loom.
{ pkgs, self, inputs }:

let
  inherit (pkgs) lib;
  loom = inputs.loom;
  loomInputs = loom.inputs;
  fx = import "${loom}/tests/lib/installer-fixtures.nix" { inherit pkgs; };
  hostVm = ../tests/fixtures/host-vm-omanix;
  tools = import ../lib/tools.nix { inherit pkgs; omanix = self; };
  flashTest = pkgs.callPackage "${loom}/pkgs/loom-flash" { releaseSigners = fx.releaseSigners; };

  installerArgs = { test = true; image = false; siloKnownHosts = "${fx.siloKey}/known_hosts"; };
  # The settings configure bakes for a release, but with the test template.
  answers = pkgs.writeText "answers-mint.json" (builtins.toJSON {
    schema = "loom.answers/v1";
    flavor = "omanix";
    host.name = "kestrel";
    user = { name = "alice"; fullName = "Alice Example"; email = "alice@example.org"; };
    locale = { timeZone = "UTC"; keyMap = "us"; language = "en_US.UTF-8"; };
    agent = { name = "ada"; harness = "claude-code"; sudo = "listed"; };
    humans.alice = { key = "@OWNER@"; owner = true; };
    theme = "tokyo-night";
    defaults = { terminal = "kitty"; browser = "chromium"; editor = "nvim"; };
    apps = [ "localsend" ];
  });

  usbStick = [
    "-device qemu-xhci,id=xhci"
    "-drive if=none,id=stick,format=raw,file=$SHARED_DIR/usb.img"
    "-device usb-storage,bus=xhci.0,drive=stick,removable=on,serial=LOOMSTICK01"
  ];

  siloNode = { config, ... }: {
    imports = [ "${loomInputs.seed-silo}/instances/silo/standalone.nix" ];
    environment.etc."ssh/ssh_host_ed25519_key" = { source = "${fx.siloKey}/ssh_host_ed25519_key"; mode = "0600"; };
    environment.etc."ssh/ssh_host_ed25519_key.pub".source = "${fx.siloKey}/ssh_host_ed25519_key.pub";
    services.openssh.hostKeys = lib.mkForce [ ];
    services.openssh.extraConfig = "HostKey /etc/ssh/ssh_host_ed25519_key";
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        interface = "eth1";
        bind-interfaces = true;
        dhcp-range = [ "192.168.1.100,192.168.1.200,1h" ];
        address = [ "/silo.test/${config.networking.primaryIPAddress}" "/silo.loom.farm/0.0.0.0" ];
        no-resolv = true;
      };
    };
    networking.firewall.allowedUDPPorts = [ 53 67 ];
    networking.firewall.allowedTCPPorts = [ 53 ];
    networking.hosts."0.0.0.0" = [ "silo.loom.farm" ];
  };

  laptopNode = { nodes, ... }: {
    environment.systemPackages = [ tools.omanix-configure flashTest pkgs.git pkgs.openssh pkgs.jq ];
    # configure check evaluates the minted host offline: every flake source
    # its lock can need is registered here, like on the stick
    system.extraDependencies = loom.lib.flakeSources self;
    nix.settings = { substituters = lib.mkForce [ ]; experimental-features = [ "nix-command" "flakes" ]; };
    virtualisation = { memorySize = 6144; cores = 2; diskSize = 4096; writableStoreUseTmpfs = false; };
    networking.hosts.${nodes.silo.networking.primaryIPAddress} = [ "silo.test" ];
    networking.hosts."0.0.0.0" = [ "silo.loom.farm" ];
    virtualisation.qemu.options = usbStick;
  };

  installerNode = { nodes, lib, ... }: {
    imports = self.lib.installer.modules installerArgs;
    virtualisation = {
      memorySize = 6144;
      cores = 4;
      diskSize = 16384;
      useEFIBoot = true;
      writableStoreUseTmpfs = false;
      emptyDiskImages = [{ size = 32768; driveConfig.deviceExtraOpts.serial = "loomdisk"; }];
      qemu.options = usbStick;
    };
    networking.networkmanager.enable = lib.mkForce false;
    networking.hosts.${nodes.silo.networking.primaryIPAddress} = [ "silo.test" ];
  };
in
pkgs.testers.runNixOSTest {
  name = "omanix-installer-e2e-omanix";
  globalTimeout = 7200;
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom; };
  nodes = { silo = siloNode; laptop = laptopNode; installer = installerNode; };
  testScript = { nodes, ... }:
    let
      # every store path the test stick supplies (the live store; a release
      # image's stick-index adds the CACHE partition)
      stickIndex = pkgs.closureInfo { rootPaths = [ nodes.installer.system.build.toplevel ]; };
    in
    ''
      import json, os, re, shlex, subprocess

      OWNER_PASS = "throwaway owner passphrase for alice 7"
      LOGIN = "correct horse battery staple 9"
      DISKPW = "an entirely different disk passphrase 3"
      REPOS = "/var/lib/silo/repos"
      SILO = "--silo ssh://git@silo.test --known-hosts /root/kh"
      ENV = "SSH_ASKPASS=/root/askpass SSH_ASKPASS_REQUIRE=force DISPLAY=:0 HOME=/root"
      MID = "2" * 32

      def prompt_re(key):
          return rf"\?\? {re.escape(key)}(?![\w.-])"

      def wait(m, regex, timeout=900):
          m.wait_for_console_text(rf"(?:{regex})|INSTALL FAILED", timeout=timeout)
          tail = m.get_console_log()[-4000:]
          assert "INSTALL FAILED" not in tail, tail

      def ask(m, key, answer, timeout=900):
          wait(m, prompt_re(key), timeout)
          m.send_console(answer + "\n")

      def option(m, needle):
          nums = re.findall(rf"^\s+(\d+)\) [^\n]*{re.escape(needle)}", m.get_console_log(), re.M)
          assert nums, f"no option mentioning {needle!r}"
          return nums[-1]

      def pick(m, key, needle, timeout=900):
          wait(m, prompt_re(key), timeout)
          m.send_console(option(m, needle) + "\n")

      def shown_sek(m):
          keys = re.findall(r"SEK1(?:-[0-9A-Z]{4}){9}", m.get_console_log())
          assert keys, "no system encryption key on the console"
          return keys[-1]

      def boot_installed(name="target"):
          st = installer.state_dir
          cmd = (
              "${pkgs.qemu_test}/bin/qemu-system-x86_64 -machine q35,accel=kvm:tcg,smm=on -cpu max -m 4096 -smp 2 "
              "-global driver=cfi.pflash01,property=secure,value=on "
              "-drive if=pflash,format=raw,unit=0,readonly=on,file=${nodes.installer.virtualisation.efi.firmware} "
              f"-drive if=pflash,format=raw,unit=1,readonly=off,file={st}/installer-efi-vars.fd "
              f"-drive file={st}/empty0.qcow2,if=none,id=target,format=qcow2,werror=report "
              "-device virtio-blk-pci,drive=target,serial=loomdisk,bootindex=1 "
              "-netdev vde,id=vlan1,sock=$QEMU_VDE_SOCKET_1 -device virtio-net-pci,netdev=vlan1,mac=52:54:00:12:01:99 "
          )
          return create_machine(cmd, name=name)

      subprocess.run(["truncate", "-s", "512M", os.path.join(installer.shared_dir, "usb.img")], check=True)
      silo.start()
      laptop.start()
      silo.wait_for_unit("sshd.service")
      silo.wait_for_unit("dnsmasq.service")
      laptop.wait_for_unit("multi-user.target")

      with subtest("configure on the laptop: mint (owner key pushes first)"):
          laptop.succeed("mkdir -p /root/k && printf '#!/bin/sh\\necho %s\\n' " + shlex.quote(shlex.quote(OWNER_PASS)) + " > /root/askpass && chmod 755 /root/askpass")
          laptop.succeed(f"ssh-keygen -q -t ed25519 -N {shlex.quote(OWNER_PASS)} -C alice@laptop -f /root/k/owner")
          laptop.succeed("cp ${fx.siloKey}/known_hosts /root/kh")
          pub = laptop.succeed("cut -d' ' -f1,2 /root/k/owner.pub").strip()
          laptop.succeed(f"sed 's|@OWNER@|{pub}|' ${answers} > /root/answers.json")
          ids = json.loads(laptop.succeed(f"omanix-configure ids --machine-id {MID} --json"))
          RID = ids["id"]
          st = json.loads(laptop.succeed(
              f"cd /root && {ENV} omanix-configure mint --answers /root/answers.json --owner-key /root/k/owner "
              f"--work /root/w --template ${hostVm} --machine-id {MID} --state-dir /root/state {SILO} --json"))
          assert st["id"] == RID and st["pushed"], st
          owner = " ".join(silo.succeed(f"cat {REPOS}/omanix/{RID}.git/.owner_key").split()[:2])
          assert owner == pub, (owner, pub)
          laptop.succeed("grep -q 'tokyo-night' /root/w/configuration.nix")

      with subtest("configure check: an offline install needs nothing the stick lacks"):
          res = json.loads(laptop.succeed(
              "omanix-configure check --repo /root/w --index ${stickIndex}/store-paths --json"))
          print(f"configure check: {res['toBuild']} derivations to build, cacheMiss = {res['cacheMiss']}")
          assert res["cacheMiss"] == [], res["cacheMiss"]
          assert res["toBuild"] > 0, res        # the per-host derivations do rebuild

      with subtest("configure sidecar, flash"):
          laptop.succeed(f"omanix-configure sidecar --state /root/state/{RID}/state.json --answers /root/answers.json --out /root/cfg --hint-unlock passphrase --json >&2")
          plan = json.loads(laptop.succeed("loom-flash plan --image ${fx.fakeRelease}/installer.raw --sidecar /root/cfg --json"))
          assert len(plan["candidates"]) == 1, plan
          stick = plan["candidates"][0]
          laptop.succeed(f"loom-flash write --device {stick['byId']} --confirm {stick['token']} --image ${fx.fakeRelease}/installer.raw --sidecar /root/cfg --json < /dev/null >&2")
          enroll_key = laptop.succeed(f"cat /root/state/{RID}/enroll.key")
          laptop.shutdown()

      with subtest("the installer installs offline (no substituter)"):
          installer.start()
          wait(installer, r"This stick configures kestrel", timeout=300)
          assert installer.succeed("nix config show substituters").strip() == "", "the installer has a substituter"
          pick(installer, "disk", "loomdisk")
          ask(installer, "disk.confirm", "kestrel")
          ask(installer, "secureboot", "no")
          pick(installer, "unlock", "Passphrase")
          ask(installer, "password.login", LOGIN)
          ask(installer, "password.login.again", LOGIN)
          ask(installer, "password.disk.same", "no")
          ask(installer, "password.disk", DISKPW)
          ask(installer, "password.disk.again", DISKPW)
          pick(installer, "agent", "Yes:")
          pick(installer, "agent.sudo", "No (recommended)")
          wait(installer, prompt_re("sek.written"))
          SEK = shown_sek(installer)
          installer.send_console("yes\n")
          ask(installer, "sek.check", SEK)
          installer.wait_for_console_text("Key confirmed")
          wait(installer, prompt_re("finish"), timeout=5400)
          text = installer.get_console_log()
          assert "Enrollment: verified" in text, text[-3000:]
          assert re.findall(r"Host: \S+ \(([0-9a-f]{32})\)", text)[-1] == RID
          ilog = installer.succeed("cat /run/loom/install.jsonl")
          installer.send_console("\n")
          installer.wait_for_shutdown()
          assert "cache.nixos.org" not in ilog

      with subtest("first boot: an omanix system, unlocked with the SEK"):
          target = boot_installed()
          target.start()
          target.wait_for_console_text("Please enter passphrase for disk", timeout=900)
          target.send_console(SEK + "\n")
          target.wait_for_unit("multi-user.target", timeout=900)
          target.succeed("test -e /run/current-system/omarchy")
          target.succeed("grep -q tokyo-night /persist/var/lib/loom/host/configuration.nix")
          target.succeed("test -e /persist/var/lib/loom/firstboot/repo-publish.done")
          target.fail("grep -rqE 'SEK1-|AGE-SECRET-KEY|correct horse' /persist/var/log/loom-install.jsonl /persist/var/lib/loom/host")

      with subtest("silo: master is the install commit; the enroll key is locked out"):
          TGIT = "$(ls -d /nix/store/*-git-[0-9]*/bin/git | head -1) -c safe.directory='*'"
          deployed = target.succeed(f"{TGIT} -C /persist/var/lib/loom/host rev-parse master").strip()
          assert silo.succeed(f"git -c safe.directory='*' -C {REPOS}/omanix/{RID}.git rev-parse master").strip() == deployed
          silo.succeed(f"cat > /root/enroll.key <<'EOF'\n{enroll_key}EOF\nchmod 600 /root/enroll.key")
          silo.succeed(f"git -c safe.directory='*' clone -q {REPOS}/omanix/{RID}.git /root/probe")
          out = silo.fail("cd /root/probe && GIT_SSH_COMMAND='ssh -i /root/enroll.key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o BatchMode=yes' "
                          f"git push ssh://git@localhost/omanix/{RID}.git HEAD:refs/heads/gate/enroll-probe 2>&1")
          assert "silo: access denied" in out, out
      target.crash()
    '';
}
