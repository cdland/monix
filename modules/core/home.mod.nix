# Wires Home Manager in as a NixOS module and applies every `homeModules`
# aspect to the primary user. Home aspects that are desktop-only gate
# themselves on `osConfig.isDesktop`.
{ self, inputs, ... }:
{
  flake.nixosModules.home-manager =
    { config, lib, ... }:
    let
      inherit (lib.attrsets) attrValues;
      inherit (lib.lists) singleton;
    in
    {
      imports = singleton inputs.home-manager.nixosModules.home-manager;

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "hm-bak";
      home-manager.extraSpecialArgs = { inherit inputs self; };

      home-manager.users.${config.primaryUser} = {
        imports = attrValues self.homeModules;

        home.username = config.primaryUser;
        home.homeDirectory = "/home/${config.primaryUser}";
        home.stateVersion = config.system.stateVersion;
      };
    };
}
