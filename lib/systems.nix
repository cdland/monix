{ self }:
{
  # Builds a NixOS configuration and exposes it as
  # `flake.nixosConfigurations.<hostName>`.
  #
  # `self.nixosSystem` is nixpkgs' `lib.nixosSystem` resolved against the
  # extended lib fixpoint, so any custom lib helpers are also available inside
  # the evaluated modules.
  systems.nixosSystem =
    hostName: module:
    {
      flake.nixosConfigurations.${hostName} = self.nixosSystem {
        modules = [
          module
          { networking.hostName = hostName; }
        ];
      };
    };
}
