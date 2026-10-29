# The omanix Plymouth theme (§f.2.3 boot visuals, §f.5): upstream's
# default/plymouth script and images, recolored from a theme palette exactly
# as upstream's omarchy-plymouth-set does at runtime (background into the
# script, the dialog images tinted to the text color), with the omanix
# wordmark instead of the omarchy logo (§f.2.8). Rebuild-time only: the
# theme is omanix.theme.boot.theme.
#
#   $out/share/plymouth/themes/<name>/   the theme (boot.plymouth.themePackages)
#   $out/share/omanix-plymouth/<name>/logo.png            the wordmark in the accent
#   $out/share/omanix-plymouth/<name>/preview-unlock.png  a still of the unlock screen
# (per theme name, so several variants can share one buildEnv)
#
# The wordmark is drawn from JetBrains Mono until omanix has a designed logo.
{
  lib,
  runCommand,
  imagemagick,
  jetbrains-mono,
  omanixFork,
  themeName ? "omanix",
  omanixTheme ? "tokyo-night",
  omanixPalette ? (import ../../../lib/theme.nix { inherit lib; }).palette "${omanixFork.src}/themes/${omanixTheme}",
}:

let
  src = "${omanixFork.src}/default/plymouth";
  font = "${jetbrains-mono}/share/fonts/truetype/JetBrainsMono-ExtraBold.ttf";
  # "r, g, b" in 0..1 with three decimals, like upstream's awk printf "%.3f"
  rgb = c: lib.concatMapStringsSep ", " (i:
    let
      n = lib.fromHexString (builtins.substring i 2 (lib.removePrefix "#" c));
      v = (n * 2000 + 255) / 510; # round(n / 255 * 1000)
    in
    "${toString (v / 1000)}.${lib.fixedWidthNumber 3 (lib.mod v 1000)}") [ 0 2 4 ];
in
runCommand "omanix-plymouth-${themeName}"
  {
    nativeBuildInputs = [ imagemagick ];
    passthru = { palette = omanixPalette; inherit themeName; };
    meta = {
      description = "omanix boot splash and unlock screen (from omarchy's, MIT)";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    d=$out/share/plymouth/themes/${themeName}
    mkdir -p $d $out/share/omanix-plymouth/${themeName}
    # -strip: no timestamps in the PNGs, so the output is reproducible
    tint() { magick "$1" -channel RGB +level-colors "$2","$2" -strip "$3"; }

    for a in bullet entry lock progress_bar; do tint ${src}/$a.png '${omanixPalette.foreground}' $d/$a.png; done
    magick ${src}/progress_box.png -strip $d/progress_box.png

    magick -background none -fill white -font ${font} -pointsize 200 label:omanix \
      -trim +repage -strip logo-white.png
    tint logo-white.png '${omanixPalette.accent}' $d/logo.png
    cp $d/logo.png $out/share/omanix-plymouth/${themeName}/logo.png

    sed -e 's/^Window.SetBackgroundTopColor.*/Window.SetBackgroundTopColor(${rgb omanixPalette.background});/' \
        -e 's/^Window.SetBackgroundBottomColor.*/Window.SetBackgroundBottomColor(${rgb omanixPalette.background});/' \
        -e 's/^# Omarchy Plymouth Theme Script/# omanix Plymouth theme script (from omarchy'"'"'s, MIT)/' \
        ${src}/omarchy.script > $d/${themeName}.script
    grep -q 'SetBackgroundTopColor(${rgb omanixPalette.background})' $d/${themeName}.script

    cat > $d/${themeName}.plymouth <<EOF
    [Plymouth Theme]
    Name=omanix
    Description=omanix splash and unlock screen
    ModuleName=script

    [script]
    ImageDir=$d
    ScriptFile=$d/${themeName}.script
    ConsoleLogBackgroundColor=0x${lib.removePrefix "#" omanixPalette.background}
    MonospaceFont=Cantarell 11
    Font=Cantarell 11
    EOF

    # The unlock screen as the script lays it out (logo centred, the entry
    # 40 px below it, the lock 15 px left of the entry at 80% of its height,
    # four bullets), for previews and the registry's preview-unlock.png.
    W=1920 H=1080
    read lw lh < <(magick identify -format '%w %h\n' $d/logo.png)
    read ew eh < <(magick identify -format '%w %h\n' $d/entry.png)
    lx=$(( (W - lw) / 2 )) ly=$(( (H - lh) / 2 ))
    ex=$(( (W - ew) / 2 )) ey=$(( ly + lh + 40 ))
    kh=$(( eh * 8 / 10 )) kw=$(( 84 * eh * 8 / 10 / 96 ))
    kx=$(( ex - kw - 15 )) ky=$(( ey + eh / 2 - kh / 2 ))
    by=$(( ey + eh / 2 - 3 ))
    magick -size ''${W}x''${H} 'xc:${omanixPalette.background}' \
      $d/logo.png -geometry +$lx+$ly -composite \
      $d/entry.png -geometry +$ex+$ey -composite \
      \( $d/lock.png -resize ''${kw}x''${kh}! \) -geometry +$kx+$ky -composite \
      \( $d/bullet.png -resize 7x7! \) -geometry +$((ex + 20))+$by -composite \
      \( $d/bullet.png -resize 7x7! \) -geometry +$((ex + 32))+$by -composite \
      \( $d/bullet.png -resize 7x7! \) -geometry +$((ex + 44))+$by -composite \
      \( $d/bullet.png -resize 7x7! \) -geometry +$((ex + 56))+$by -composite \
      -strip $out/share/omanix-plymouth/${themeName}/preview-unlock.png
  ''
