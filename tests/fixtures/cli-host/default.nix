# Host modules. List every file explicitly (no readDir), so a reader can trace them.
{
  imports = [ ./plugins.nix ./persist.nix ./vm.nix ];
}
