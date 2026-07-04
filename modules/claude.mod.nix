# Claude Code global instructions (~/.claude/CLAUDE.md), versioned here
# instead of hand-edited in place. Only this config file is managed —
# everything else under ~/.claude (memory, transcripts, credentials) is
# mutable state Claude writes to live and must stay unmanaged. Gated on
# isDesktop to match where claude-code is installed (packages-dev-extras).
{
  flake.homeModules.claude =
    { lib, osConfig, ... }:
    let
      inherit (lib.modules) mkIf;
    in
    {
      config = mkIf osConfig.isDesktop {
        home.file.".claude/CLAUDE.md" = {
          # Adopt the pre-existing hand-written file on first switch.
          force = true;
          text = ''
            # Global instructions

            ## Commits

            Never add Co-Authored-By, Claude-Session, "Generated with Claude Code", or any similar trailers/attribution lines to commit messages or PR bodies. Plain messages only.

            ## Permission denials are vetoes

            A denial vetoes the *outcome*, not just the specific tool call. Never achieve the same effect through a different tool (sed/bash instead of a denied Edit, a wrapper script instead of a denied command, etc.). A denial usually means the user dislikes the action or thinks you're on a lost path — but it can also be a misclick while switching windows. Either way the response is the same: stop, explain what you were trying to do and why, and let the user decide — they'll re-approve if it was a misclick. Pass this rule along in the prompt of any subagent that will take actions.

            ## Economics

            Budget and usage limits are real constraints: weigh the token cost of your approach, and delegate execution to cheaper subagents (haiku/sonnet) when they'd do the job just as well. Never trade quality for cost — the savings only count if the work is equally good.
          '';
        };
      };
    };
}
