# quirk apple-spi-keyboard (fork/hw-quirks.toml; option quirks.appleSpiKeyboard): MacBooks with an SPI keyboard: its modules in the initrd (to type the disk passphrase).
# Upstream: install/hardware/apple/fix-spi-keyboard.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.appleSpiKeyboard;
in
{
  options.omanix.hardware.quirks.appleSpiKeyboard = {
    enable = lib.mkEnableOption "the apple-spi-keyboard hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.initrd.kernelModules = [ "applespi" "intel_lpss_pci" "spi_pxa2xx_platform" "spi_pxa2xx_pci" ];
  };
}
