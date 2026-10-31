# Test-only (tests/fixtures/host-vm-omanix, after loom's tests/fixtures/host-vm):
# what makes an installed omanix host drivable by the NixOS test driver after
# the installer reboots into it. The installer's test variant renders this
# template; release images use templates/host. checks.reference-templates
# keeps the rest identical.
{ lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/testing/test-instrumentation.nix"
    "${modulesPath}/profiles/qemu-guest.nix"
  ];
  # ~900 MiB less to copy in every install test; a VM needs no firmware.
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.firmware = lib.mkForce [ ];
  # The last console= is /dev/console: the disk prompt must reach the serial line.
  boot.kernelParams = lib.mkAfter [ "console=ttyS0,115200" ];
}
