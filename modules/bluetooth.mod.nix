# Bluetooth on desktops. The GUI is blueberry (waybar's on-click target),
# installed via the desktop packages bundle; the source's additional blueman
# service was redundant with it and is dropped.
{
  flake.nixosModules.bluetooth =
    { config, lib, ... }:
    let
      inherit (lib.modules) mkIf;
    in
    {
      config = mkIf config.isDesktop {
        hardware.bluetooth.enable = true;
      };
    };
}
