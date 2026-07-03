# Terminal (replaces kitty). font-family
# falls back from the source's "ComicCodeLigatures Nerd Font" (a proprietary
# font installed manually, not shippable) to CaskaydiaMono, which fonts.mod.nix
# installs. Install Comic Code to ~/.local/share/fonts and change this to
# restore the original. Theming removed in the simplification pass; ghostty
# uses its default theme.
{
  flake.homeModules.ghostty =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      inherit (lib.modules) mkIf;
      inherit (lib.meta) getExe;
    in
    {
      config = mkIf osConfig.isDesktop {
        programs.ghostty = {
          enable = true;

          settings = {
            window-padding-x = 14;
            window-padding-y = 14;
            background-opacity = 0.95;
            window-decoration = "none";

            font-family = "CaskaydiaMono Nerd Font";
            font-size = 10;

            keybind = [ "ctrl+k=reset" ];

            # Run as a GTK single-instance daemon (see the systemd service
            # below): further launches just open a new window in the running
            # process instead of paying startup cost each time.
            gtk-single-instance = true;
            quit-after-last-window-closed = false;
            initial-window = false;
          };

          # The upstream unit (systemd.enable default) would duplicate our
          # ghostty.service, which starts after the session env import instead.
          systemd.enable = false;
        };

        # Ordered after hyprland-session.target, which only becomes active
        # once Hyprland's own systemd startup hook has imported the session
        # environment (WAYLAND_DISPLAY, etc.) into the systemd user manager
        # — see `wayland.windowManager.hyprland.systemd` in hyprland.mod.nix.
        systemd.user.services.ghostty = {
          Unit = {
            Description = "Ghostty terminal daemon";
            After = [ "hyprland-session.target" ];
            PartOf = [ "hyprland-session.target" ];
          };
          Service = {
            ExecStart = getExe config.programs.ghostty.package;
            Restart = "on-failure";
          };
          Install.WantedBy = [ "hyprland-session.target" ];
        };
      };
    };
}
