{ lib, rustPlatform, fetchFromGitHub, installShellFiles, stdenv }:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ttfx";
  version = "0.5.1";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "ttfx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/cECljrthspJsg6fgWMm4QIv8V3FJLuP/pbZoRKFVAc=";
  };

  cargoHash = "sha256-xSv2a0Q1biE20cOHkSOADxFfRNYKH/1MNCA03hQX9pE=";

  nativeBuildInputs = [ installShellFiles ];
  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd ttfx \
      --bash <($out/bin/ttfx --print-completion bash) \
      --zsh <($out/bin/ttfx --print-completion zsh)
  '';

  meta = {
    description = "Terminal text effects as a single static binary (Rust port of terminaltexteffects)";
    homepage = "https://github.com/omacom/ttfx";
    license = lib.licenses.mit;
    mainProgram = "ttfx";
  };
})
