# SSH public keys used both for `agenix` secret encryption and for SSH access.
#
#   Host keys  - on each machine run `cat /etc/ssh/ssh_host_ed25519_key.pub`.
#                On a brand-new machine, generate them first with `ssh-keygen -A`,
#                add the key here, then `agenix -r` to rekey existing secrets.
#   Admin keys - your personal public key(s), e.g. `cat ~/.ssh/id_ed25519.pub`.
#
# This file is the single source of truth for keys: it is imported both by
# `secrets.nix` (consumed by the agenix CLI) and by `modules/keys.mod.nix`
# (which exposes the keys as flake outputs `keys` and `keys-admin`).
{
  hosts = {
    fw0 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINLRVD/zQrWUetJ3VxVJtZ6Zc6wOck05M9l0opF/Emb8 fw0";
    fw3 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0HL6IH1F5hiNKQ58mIPozF4ov20BfZB4lT/cA6B8Ik fw3";
  };

  admin = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF7/0+EtR35ZsgmHq0IXNY5gQ1SlTUGSRz+P38qGfn0F dylan@dylandavid.com"
  ];
}
