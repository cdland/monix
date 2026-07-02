# git + gh. Uses `programs.git.settings`: home-manager renamed `extraConfig`
# to `settings` and deprecated `userName`/`userEmail` in favour of
# `settings.user.{name,email}` (verified against home-manager master).
{
  flake.homeModules.git =
    { ... }:
    {
      programs.git = {
        enable = true;

        settings = {
          user.name = "Dylan";
          user.email = "dylan@cleary.org";

          init.defaultBranch = "main";
          pull.rebase = true;

          credential.helper = "store";
        };
      };

      programs.gh = {
        enable = true;
        gitCredentialHelper.enable = true;
      };
    };
}
