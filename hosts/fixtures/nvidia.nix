# ref-nvidia: a desktop with an NVIDIA GPU (GSP, open modules) next to Intel
# graphics, as loom-detect/hostgen would write it.
{
  loom.hardware.facts = { gpu = [ "intel" "nvidia" ]; cpu.vendor = "intel"; };
  omanix.hardware.quirks = {
    nvidia.enable = true;
    hybridGpu.enable = true;
    intelVideo.enable = true;
  };
}
