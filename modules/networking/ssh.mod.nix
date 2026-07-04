{ self, ... }:
{
  flake.nixosModules.ssh =
    { lib, ... }:
    let
      inherit (lib.modules) mkDefault;
    in
    {
      services.openssh = {
        enable = true;

        settings = {
          PasswordAuthentication = mkDefault false;
          KbdInteractiveAuthentication = mkDefault false;
          PermitRootLogin = mkDefault "prohibit-password";
        };
      };

      users.users.root.openssh.authorizedKeys.keys = self.keys-admin;
    };
}
