# Interactive zsh with the grml config
# (nushell remains the login shell on fw3; zsh is the configured interactive
# fallback). The grml prompt gains a nix-shell indicator.
{
  flake.homeModules.zsh =
    { pkgs, ... }:
    {
      programs.zsh = {
        enable = true;

        envExtra = ''
          setopt NO_GLOBAL_RCS
        '';

        initContent = ''
          source "${pkgs.grml-zsh-config}/etc/zsh/zshrc"

          # history
          HISTSIZE=10000000

          # nix-shell indicator
          zstyle ':prompt:grml:right:setup' items
          function nix_shell_prompt () {
            REPLY=''${IN_NIX_SHELL+"(nix-shell) "}
          }
          grml_theme_add_token nix-shell-indicator -f nix_shell_prompt '%F{magenta}' '%F'
          zstyle ':prompt:grml:left:setup' items rc nix-shell-indicator change-root user at host path vcs percent
        '';
      };
    };
}
