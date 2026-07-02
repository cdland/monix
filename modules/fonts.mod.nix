# Fonts: CaskaydiaMono Nerd Font is what the
# waybar/ghostty/tofi configs reference. `noto-fonts-color-emoji` is
# the current attribute name (noto-fonts-emoji is a deprecated alias).
#
# The source additionally forced "ComicCodeLigatures Nerd Font" as the
# monospace default; that font is proprietary and manually installed, so it is
# not shippable here. Install it to ~/.local/share/fonts to use it.
{
  flake.nixosModules.fonts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib.modules) mkIf;
    in
    {
      config = mkIf config.isDesktop {
        fonts.enableDefaultPackages = true;

        fonts.packages = [
          pkgs.noto-fonts
          pkgs.noto-fonts-color-emoji
          pkgs.nerd-fonts.caskaydia-mono
        ];

        fonts.fontconfig.defaultFonts = {
          monospace = [ "CaskaydiaMono Nerd Font" ];
          sansSerif = [ "Noto Sans" ];
          serif = [ "Noto Serif" ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
    };
}
