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
        };
      };
    };
}
