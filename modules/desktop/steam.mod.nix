# Steam gaming aspect. Inert until a host sets `programs.steam.enable = true`.
{
  flake.nixosModules.steam =
    { config, lib, ... }:
    let
      inherit (lib.modules) mkDefault mkIf;
    in
    {
      config = mkIf config.programs.steam.enable {
        programs.steam = {
          remotePlay.openFirewall = mkDefault true;
          dedicatedServer.openFirewall = mkDefault true;
          localNetworkGameTransfers.openFirewall = mkDefault true;
        };
      };
    };
}
