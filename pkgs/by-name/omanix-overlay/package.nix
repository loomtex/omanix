# omanix-overlay: runtime overlays (DESIGN §f.4.3-§f.4.8). Stdlib python; the
# pytest suite runs in the build (checks.omanix-overlay keeps it in the gate).
{ lib, python3Packages }:

python3Packages.buildPythonApplication {
  pname = "omanix-overlay";
  version = "0.1.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./omanix_overlay ./tests ./pyproject.toml ];
  };

  build-system = [ python3Packages.setuptools ];
  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  meta = {
    description = "omanix runtime overlays: init, kv, hypr-scale, rebase, settle, reset, state";
    mainProgram = "omanix-overlay";
    license = lib.licenses.mit;
  };
}
