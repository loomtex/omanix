# The omanix SDDM theme (§f.2.3 boot visuals, §f.2.9 greeter): upstream's
# default/sddm/omarchy Main.qml recolored like upstream's
# omarchy-plymouth-set does (background into the QML, the images shared with
# the Plymouth theme, the failed-login images tinted red), with the omanix
# wordmark. Installed as share/sddm/themes/<name>.
{
  lib,
  runCommand,
  imagemagick,
  omanixFork,
  omanix-plymouth,
  themeName ? "omanix",
  omanixTheme ? "tokyo-night",
  omanixSplash ? omanix-plymouth.override { inherit omanixTheme; },
}:

let
  src = "${omanixFork.src}/default/sddm/omarchy";
  omanixPalette = omanixSplash.palette;
  ply = "${omanixSplash}/share/plymouth/themes/${omanixSplash.themeName}";
in
runCommand "omanix-sddm-theme-${themeName}"
  {
    nativeBuildInputs = [ imagemagick ];
    passthru = { palette = omanixPalette; };
    meta = {
      description = "omanix SDDM greeter theme (from omarchy's, MIT)";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    d=$out/share/sddm/themes/${themeName}
    mkdir -p $d
    sed -e 's/#1a1b26/${omanixPalette.background}/g' ${src}/Main.qml > $d/Main.qml
    grep -q '"${omanixPalette.background}"' $d/Main.qml

    for a in logo bullet entry lock; do cp ${ply}/$a.png $d/; done
    for a in entry lock; do
      magick ${ply}/$a.png -channel RGB +level-colors '${omanixPalette.red}','${omanixPalette.red}' -strip $d/$a-failed.png
    done

    cp ${src}/theme.conf $d/theme.conf
    cat > $d/metadata.desktop <<EOF
    [SddmGreeterTheme]
    Name=omanix
    Description=omanix login (from omarchy's terminal-style theme)
    Author=omanix
    Type=sddm-theme
    Version=1.0
    QtVersion=6
    MainScript=Main.qml
    ConfigFile=theme.conf
    EOF
  ''
