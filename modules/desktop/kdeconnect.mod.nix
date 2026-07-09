# KDE Connect: phone <-> desktop pairing (notifications, clipboard, file
# transfer, media control). Not in the config-less package bundles because it
# carries real configuration: the NixOS module opens its LAN discovery/transfer
# ports (1714-1764 TCP+UDP) on desktops — acceptable there, where the firewall
# already allows LAN service ports (see ssh.mod.nix's desktop stance), and
# never on servers (gated on isDesktop, so fw0's zero-inbound posture is
# untouched). Pairing happens over the local network the devices share.
{
  flake.nixosModules.kdeconnect =
    { config, lib, ... }:
    {
      config = lib.modules.mkIf config.isDesktop {
        programs.kdeconnect.enable = true;
      };
    };

  # The user-session half: kdeconnectd plus the tray indicator (DMS renders
  # tray items via StatusNotifier, which is what the indicator speaks).
  flake.homeModules.kdeconnect =
    { lib, osConfig, ... }:
    {
      config = lib.modules.mkIf osConfig.isDesktop {
        services.kdeconnect = {
          enable = true;
          indicator = true;
        };
      };
    };
}
