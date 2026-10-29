# ref-laptop: an Intel laptop (battery, SOF audio, Wi-Fi 7), as
# loom-detect/hostgen would write it.
{
  loom.hardware.facts = { gpu = [ "intel" ]; cpu.vendor = "intel"; battery = true; };
  omanix.hardware.quirks = {
    intelVideo.enable = true;
    intelThermald.enable = true;
    intelSof.enable = true;
    intelWifi7Eht.enable = true;
  };
  omanix.input = { layouts = [ "us" "de:nodeadkeys" ]; touchpad.naturalScroll = true; };
  omanix.fonts.size = 11;
}
