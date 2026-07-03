# Terminal (replaces kitty). font-family
# falls back from the source's "ComicCodeLigatures Nerd Font" (a proprietary
# font installed manually, not shippable) to CaskaydiaMono, which fonts.mod.nix
# installs. Install Comic Code to ~/.local/share/fonts and change this to
# restore the original. Theming removed in the simplification pass; ghostty
# uses its default theme.
{
  flake.homeModules.ghostty =
    {
      lib,
      osConfig,
      ...
    }:
    let
      inherit (lib.modules) mkIf;
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
          };

          # Daemon flags (gtk-single-instance, initial-window, etc.) must not
          # live in the config file: that file is also read by every plain
          # `ghostty` invocation (e.g. the SUPER+RETURN keybind), and
          # initial-window=false there suppressed windows for normal launches.
          # Those flags belong only on the daemon's ExecStart, which is why we
          # use upstream's systemd unit (default `systemd.enable = true`)
          # instead of hand-rolling one. It's WantedBy=graphical-session.target
          # and After=graphical-session.target, which is safe now that UWSM
          # (not this module's own `hyprland-session.target` hook, which is
          # disabled — see `wayland.windowManager.hyprland.systemd` in
          # hyprland.mod.nix) brings up `graphical-session.target` only after
          # `uwsm finalize` has exported session vars.
        };
      };
    };
}
