# Every key that can push to this repo, sign for it, or decrypt its secrets.
# Change only with `loom keys`; it regenerates .authorized_keys, CODEOWNERS,
# allowed_signers and .sops.yaml.
{
  loom.keys = {
    humans."alice" = { key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAMLIzBWFErPQVAwouoB+KoZCRe8MpP6Tkc5GKiWXzpN alice@example"; owner = true; };
    host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHNiGuZ+v/oIJopVZurK7B7sMXTjTXf8S4qPl6iR5uDu root@example";
    agents."ada" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICipBz6vu42lYIUv+NT+8Zu/z2XpBEE+fgXR81YBkWGn ada@example";
    enroll = null;                        # set only in the mint commit
  };
}
