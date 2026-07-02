# Exposes the SSH public keys from ./keys.nix as flake outputs so modules can
# reference them (e.g. for authorizedKeys). `self.keys` / `self.keys-admin`.
let
  keys = import ../keys.nix;
in
{
  flake.keys = keys.hosts;
  flake.keys-admin = keys.admin;
}
