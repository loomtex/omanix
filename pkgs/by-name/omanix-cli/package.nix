# omanix-cli: `omanix`, the CLI the resident and experts drive (DESIGN §h.8),
# and `omanix-preview`, the human-session helper behind `omanix try`.
# Python stdlib plus tree-sitter-nix for the comment-preserving editor (U19);
# the pytest suite runs in the build. Tools it calls are on PATH; loom's
# (`loom propose`) and the session's (hyprctl, omarchy-*) come from the
# system.
{ lib, python3Packages, nix, git, nixfmt, nvd, sops, util-linux, omanix-overlay, omanix-hw-probe }:

python3Packages.buildPythonApplication {
  pname = "omanix-cli";
  version = "0.1.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./omanix_cli ./tests ./pyproject.toml ./commands.json ];
  };

  postPatch = ''
    cp commands.json omanix_cli/commands.json
  '';

  build-system = [ python3Packages.setuptools ];
  dependencies = [ python3Packages.tree-sitter python3Packages.tree-sitter-grammars.tree-sitter-nix ];
  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  makeWrapperArgs = [
    "--suffix" "PATH" ":" (lib.makeBinPath [ nix git nixfmt nvd sops util-linux omanix-overlay omanix-hw-probe ])
  ];

  postInstall = ''
    install -Dm644 commands.json $out/share/omanix-cli/commands.json
  '';

  meta = {
    description = "omanix: context, options, where, set, plugin, app, check, propose, try, …";
    mainProgram = "omanix";
    license = lib.licenses.mit;
  };
}
