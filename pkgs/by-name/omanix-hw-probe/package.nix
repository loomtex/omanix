# omanix-hw-probe: evaluates fork/hw-quirks.toml's declarative probes against
# /sys, /proc and `lspci -nn` (DESIGN §f.2.6). Stdlib python; never runs
# omarchy code. The pytest suite (one sysfs fixture per probe) runs in the
# build; checks.hw-quirks keeps it in the gate.
{ lib, python3Packages, pciutils, omanixFork }:

python3Packages.buildPythonApplication {
  pname = "omanix-hw-probe";
  version = "0.1.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./omanix_hw_probe ./tests ./pyproject.toml ];
  };

  postPatch = ''
    cp ${omanixFork.forkDir}/hw-quirks.toml omanix_hw_probe/hw-quirks.toml
  '';

  build-system = [ python3Packages.setuptools ];
  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  makeWrapperArgs = [ "--prefix" "PATH" ":" (lib.makeBinPath [ pciutils ]) ];

  meta = {
    description = "Which omanix hardware quirks match this machine";
    mainProgram = "omanix-hw-probe";
    license = lib.licenses.mit;
  };
}
