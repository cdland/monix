# DankMaterialShell: one quickshell-based desktop shell providing the bar,
# notifications, launcher (spotlight), OSD, control center, lock screen with
# idle handling, wallpaper manager, clipboard history, and polkit agent. It
# replaces the previous waybar/mako/tofi/hyprpaper/hyprlock/hypridle/clipse
# aspects. Started from Hyprland via `dms run` (see hyprland.mod.nix).
#
# The shell itself stays on nixpkgs' `programs.dms-shell` module. The
# `dank-material-shell` flake input is used only for its `nixosModules.greeter`
# (nixpkgs does not ship a DMS greetd greeter) — `programs.dank-material-shell`
# (the flake's own shell option) is deliberately left disabled so we don't run
# two DMS shells.
{ inputs, ... }:
{
  flake.nixosModules.dank =
    { config, lib, ... }:
    let
      inherit (lib.modules) mkIf;
    in
    {
      imports = [ inputs.dank-material-shell.nixosModules.greeter ];

      config = mkIf config.isDesktop {
        programs.dms-shell.enable = true;

        programs.dank-material-shell.greeter = {
          enable = true;
          compositor.name = "hyprland";
        };

        # systemd user units don't inherit the session's XDG_DATA_DIRS on
        # NixOS; without it the DMS launcher finds no .desktop entries.
        systemd.user.services.dms.environment.XDG_DATA_DIRS =
          "/etc/profiles/per-user/${config.primaryUser}/share:/run/current-system/sw/share";
      };
    };
}
