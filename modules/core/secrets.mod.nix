{ inputs, ... }:
{
  # Alias `secrets.<name>` to `age.secrets.<name>` so host/module code can use
  # the shorter `config.secrets.foo.path`.
  flake.commonModules.secrets =
    { lib, ... }:
    let
      inherit (lib.lists) singleton;
      inherit (lib.modules) mkAliasOptionModule;
    in
    {
      imports = singleton (mkAliasOptionModule [ "secrets" ] [ "age" "secrets" ]);
    };

  flake.nixosModules.secrets =
    { lib, ... }:
    let
      inherit (lib.lists) singleton;
    in
    {
      imports = singleton inputs.agenix.nixosModules.age;

      # Decrypt secrets using this host's SSH host key. The matching public key
      # must be present in keys.nix and secrets must be encrypted to it.
      age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
}
