{
  lib, rustPlatform, fetchFromGitHub, pkg-config, nasm, wrapGAppsHook4,
  gtk4, libadwaita, dbus, libdrm, libgbm, libva, libxkbcommon, libGL, vulkan-loader, wayland, openssh,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gliff";
  version = "0.4.1";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "gliff";
    tag = "v${finalAttrs.version}";
    hash = "sha256-v2EhlYP1hjp9bdoFIKbYyTWdOjx8sjjCAq66s3I5iZA=";
  };

  cargoHash = "sha256-eM8h3tFay3KVe5dS/4BqCt4vHFFFeF/geuUogQRnB4U=";

  nativeBuildInputs = [ pkg-config nasm wrapGAppsHook4 ];
  buildInputs = [ gtk4 libadwaita dbus libdrm libgbm libva libxkbcommon libGL vulkan-loader wayland ];
  doCheck = false;

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vulkan-loader libGL libva ]}
      --prefix PATH : ${lib.makeBinPath [ openssh ]}
    )
  '';

  meta = {
    description = "Hyprland remote desktop over SSH (GPU H.264, 4:4:4)";
    homepage = "https://github.com/omacom/gliff";
    license = with lib.licenses; [ mit bsd2 ];
    platforms = lib.platforms.linux;
  };
})
