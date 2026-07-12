{ self, ... }:
{
  flake.nixosModules.users =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (lib.lists) optionals;
    in
    {
      # Users are declared here; passwords are set imperatively (`passwd`).
      users.users.${config.primaryUser} = {
        isNormalUser = true;
        description = config.primaryUser;

        extraGroups = [
          "wheel"
        ]
        ++ optionals config.isDesktop [
          "networkmanager"
          "video"
          "audio"
          "input"
        ];

        openssh.authorizedKeys.keys = self.keys-admin;
      };
    };
}
