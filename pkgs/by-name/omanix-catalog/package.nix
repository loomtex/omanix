# omanix-catalog: assembles and validates a host's catalogs (DESIGN §h.9);
# modules/omanix/catalog.nix runs it at build time over values from the
# host's own evaluation. Stdlib python; never runs omarchy code.
{ lib, runCommand, python3, makeWrapper }:

runCommand "omanix-catalog-0.1.0"
  {
    nativeBuildInputs = [ makeWrapper ];
    src = ./omanix_catalog.py;
    meta = {
      description = "Assemble and validate omanix catalogs";
      mainProgram = "omanix-catalog";
    };
  }
  ''
    install -Dm644 $src $out/lib/omanix-catalog/omanix_catalog.py
    makeWrapper ${python3}/bin/python3 $out/bin/omanix-catalog --add-flags "-I $out/lib/omanix-catalog/omanix_catalog.py"
  ''
