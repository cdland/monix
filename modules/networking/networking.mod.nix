{
  flake.nixosModules.networking =
    { config, lib, ... }:
    let
      inherit (lib.modules) mkDefault mkIf;
    in
    {
      networking.firewall.enable = mkDefault true;
      networking.nftables.enable = mkDefault true;

      # Desktops use NetworkManager + systemd-resolved; servers rely on the
      # DHCP configured by their generated hardware-configuration.nix.
      networking.networkmanager.enable = mkIf config.isDesktop true;
      services.resolved.enable = mkIf config.isDesktop true;
    };
}
