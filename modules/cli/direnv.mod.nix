{
  flake.homeModules.direnv =
    { ... }:
    {
      # Shell hooks (bash, nushell, ...) come from home-manager's
      # enable*Integration defaults, which are all on.
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    };
}
