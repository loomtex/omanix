# vm-test: a QEMU/KVM guest (the demo and test VMs).
{
  loom.hardware.facts = { virt = "kvm"; gpu = [ "other" ]; };
  omanix.hardware.quirks.vmNoAnimations.enable = true;
}
