{
  flake.commonModules.boot =
    { lib, ... }:
    let
      inherit (lib.modules) mkDefault;
    in
    {
      boot.loader.systemd-boot.enable = mkDefault true;
      boot.loader.systemd-boot.configurationLimit = mkDefault 5;
      boot.loader.efi.canTouchEfiVariables = mkDefault true;

      # Use the systemd-based initrd everywhere.
      boot.initrd.systemd.enable = mkDefault true;
    };
}
