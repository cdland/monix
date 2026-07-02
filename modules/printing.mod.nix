# CUPS printing with mDNS discovery. Inert until a host sets
# `services.printing.enable = true`.
{
  flake.nixosModules.printing =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib.modules) mkIf;
    in
    {
      config = mkIf config.services.printing.enable {
        services.printing.drivers = [
          pkgs.cups-filters
          pkgs.cups-browsed
          pkgs.hplip
        ];

        services.avahi = {
          enable = true;
          nssmdns4 = true;
          openFirewall = true;
        };
      };
    };
}
