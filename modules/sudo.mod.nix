{
  flake.nixosModules.sudo =
    { lib, ... }:
    let
      inherit (lib.modules) mkDefault;
    in
    {
      security.sudo.enable = mkDefault true;
      security.sudo.wheelNeedsPassword = mkDefault true;

      # Required by the desktop session (polkit agents) and harmless on servers.
      security.polkit.enable = true;
    };
}
