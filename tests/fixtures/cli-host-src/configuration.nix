# Preferences for this machine. Imports the rest, so every file the system
# uses is reachable from here.
{ lib, pkgs, ... }:

{
  imports = [
    ./machine.nix
    ./keys.nix
    ./hardware.nix
    ./modules
  ];

  loom.user = {
    name = "alice";
    fullName = "Alice Example";
    email = "alice@example.org";
  };
  loom.locale = {
    timeZone = "UTC";
    keyMap = "us";
    language = "en_US.UTF-8";
  };
  loom.agent = {
    name = "ada";
    harness = "claude-code";
    sudo = "listed"; # D8: written explicitly
  };

  omanix.defaults = {
    terminal = "alacritty";
    browser = "chromium";
    editor = "nvim";
  };

  # Below this line: changes made by the agent or by you. Each one was approved on a card.
}
