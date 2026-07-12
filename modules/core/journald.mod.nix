# Bound the persistent journal. journald's default cap is 10% of the
# filesystem (up to 4G), which on a 2TB root means gigabytes of logs
# surviving forever; 1G is months of history on these machines.
{
  flake.nixosModules.journald =
    { lib, ... }:
    {
      services.journald.extraConfig = lib.modules.mkDefault ''
        SystemMaxUse=1G
      '';
    };
}
