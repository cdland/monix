# SSH public keys used both for `agenix` secret encryption and for SSH access.
# Replace every placeholder below with real keys BEFORE deploying or creating secrets.
#
#   Host keys  - on each machine run `cat /etc/ssh/ssh_host_ed25519_key.pub`.
#                On a brand-new machine, generate them first with `ssh-keygen -A`.
#   Admin keys - your personal public key(s), e.g. `cat ~/.ssh/id_ed25519.pub`.
#
# This file is the single source of truth for keys: it is imported both by
# `secrets.nix` (consumed by the agenix CLI) and by `modules/keys.mod.nix`
# (which exposes the keys as flake outputs `keys` and `keys-admin`).
{
  hosts = {
    fw3 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAREPLACE_WITH_FW3_HOST_KEY fw3";
    vs0 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAREPLACE_WITH_VS0_HOST_KEY vs0";
  };

  admin = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID88DMnwS1GgquQmaSs8ez/x+0EhI8H45INknbZC8V8P clyd@clyd.org"
  ];
}
