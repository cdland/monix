# git + gh.
{
  flake.homeModules.git =
    { ... }:
    {
      programs.git = {
        enable = true;

        settings = {
          user.name = "Dylan Cleary";
          user.email = "dylan@dylanc.com";

          init.defaultBranch = "main";
          pull.rebase = true;

          # Credentials are handled by gh (below) — no plaintext
          # `credential.helper = store`.
        };
      };

      programs.gh = {
        enable = true;
        gitCredentialHelper.enable = true;
      };
    };
}
