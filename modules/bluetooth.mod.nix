# Bluetooth on desktops. The GUI is DankMaterialShell's control center (see
# dank.mod.nix), which owns pairing/connect UI; blueman's tray applet was
# dropped from packages.mod.nix as redundant with it (its /etc/xdg/autostart
# entry was also autostarting itself under UWSM, which honors XDG autostart
# unlike the prior non-UWSM session). Use `bluetoothctl` for anything the
# control center doesn't cover.
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
