# tobi/try ("fresh directories for every vibe"); nixpkgs' `try` is a different
# program (binpash/try), so this is try-tobi with binary name `try` (facts §4).
{ lib, stdenvNoCC, fetchFromGitHub, ruby, makeWrapper }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "try-tobi";
  version = "1.10.1";

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "try";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ZSt6LSp0AQTbdN86lJGJPWcx6oFR63AFi4s8Vjr5a5o=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 try.rb $out/lib/try-tobi/try.rb
    install -Dm644 lib/tui.rb $out/lib/try-tobi/lib/tui.rb
    install -Dm644 lib/fuzzy.rb $out/lib/try-tobi/lib/fuzzy.rb
    makeWrapper ${lib.getExe ruby} $out/bin/try --add-flags $out/lib/try-tobi/try.rb
    runHook postInstall
  '';

  meta = {
    description = "Fresh directories for every vibe";
    homepage = "https://github.com/tobi/try";
    license = lib.licenses.mit;
    mainProgram = "try";
    platforms = lib.platforms.unix;
  };
})
