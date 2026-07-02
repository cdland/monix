{
  flake.commonModules.host =
    { lib, ... }:
    let
      inherit (lib.options) mkOption;
      inherit (lib.types) bool str;
    in
    {
      options.isDesktop = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether this host is a desktop/workstation. When false (the default)
          the host is treated as a server. Desktop-only modules gate their
          configuration on this option.
        '';
      };

      options.primaryUser = mkOption {
        type = str;
        default = "dylan";
        description = "Login name of the primary, human, admin user of the host.";
      };
    };
}
