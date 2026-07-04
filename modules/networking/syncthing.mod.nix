# Syncthing for the primary user. Inert until a host sets
# `services.syncthing.enable = true`.
{
  flake.nixosModules.syncthing =
    { config, lib, ... }:
    let
      inherit (lib.modules) mkDefault mkIf;
    in
    {
      config = mkIf config.services.syncthing.enable {
        services.syncthing = {
          user = mkDefault config.primaryUser;
          dataDir = mkDefault "/home/${config.primaryUser}";
          configDir = mkDefault "/home/${config.primaryUser}/.config/syncthing";
          openDefaultPorts = true;
        };
      };
    };
}
