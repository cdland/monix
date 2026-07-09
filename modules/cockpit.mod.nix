# Cockpit: the user's primary interactive Claude Code session lives on the
# host that enables this, inside tmux, attached over tailnet SSH from any
# machine. The session runs as the primary user with normal interactive
# permission prompts — it is the human's seat, not an autonomous agent, so it
# carries full user privileges (contrast with the locked-down fleet workers
# of agent-vm.mod.nix). Usage: `ssh fw0` then `tmux new -As main`.
#
# The agent tooling itself (claude-code, codex, CLAUDE.md) comes from the
# existing home aspects in packages.mod.nix / claude.mod.nix, which gate on
# `isDesktop || cockpit.enable`.
{ inputs, ... }:
{
  flake.homeModules.cockpit =
    { lib, osConfig, ... }:
    let
      guide = import ../lib/fleet-guide.nix;
      inherit (lib.modules) mkIf;
    in
    {
      config = mkIf osConfig.cockpit.enable {
        home.file."cockpit/AGENTS.md" = {
          force = true;
          text = guide.system + guide.pilot;
        };
        home.file."cockpit/CLAUDE.md" = {
          force = true;
          text = "@AGENTS.md\n";
        };
      };
    };

  flake.nixosModules.cockpit =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib.lists) singleton;
      inherit (lib.modules) mkIf;
      inherit (lib.options) mkEnableOption;
    in
    {
      options.cockpit.enable = mkEnableOption "the persistent cockpit session role on this host";

      config = mkIf config.cockpit.enable {
        # tmux is the session's persistence layer; the binary is already
        # system-wide (packages-shell-utils), this adds the /etc config.
        programs.tmux.enable = true;
        programs.tmux.historyLimit = 50000;

        # The cockpit is where secrets get created/rotated (`agenix -e ...`
        # from the repo root) — fleet credentials in particular originate
        # here (`claude setup-token`, Codex's auth.json).
        environment.systemPackages = singleton inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
    };
}
