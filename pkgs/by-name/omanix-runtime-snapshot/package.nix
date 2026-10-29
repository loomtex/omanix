# omanix-runtime-snapshot <area>: the loom.snapshot/v1 the chat surface
# attaches for "make it stick" (§f.4.6). Lives in omanix-overlay's python
# package (it shares the overlay table and snapshot sha); this is its own
# package so the chat surface can depend on it alone.
{ runCommand, omanix-overlay }:

runCommand "omanix-runtime-snapshot-${omanix-overlay.version}"
  {
    meta = omanix-overlay.meta // {
      description = "Print the typed runtime snapshot of one area (loom.snapshot/v1)";
      mainProgram = "omanix-runtime-snapshot";
    };
  }
  ''
    install -d $out/bin
    ln -s ${omanix-overlay}/bin/omanix-runtime-snapshot $out/bin/omanix-runtime-snapshot
  ''
