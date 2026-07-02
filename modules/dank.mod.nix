# DankMaterialShell: one quickshell-based desktop shell providing the bar,
# notifications, launcher (spotlight), OSD, control center, lock screen with
# idle handling, wallpaper manager, clipboard history, and polkit agent. It
# replaces the previous waybar/mako/tofi/hyprpaper/hyprlock/hypridle/clipse
# aspects. Started from Hyprland via `dms run` (see hyprland.mod.nix).
{
  flake.nixosModules.dank =
    { config, lib, ... }:
    let
      inherit (lib.modules) mkIf;
    in
    {
      config = mkIf config.isDesktop {
        programs.dms-shell.enable = true;
      };
    };
}
