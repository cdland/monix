{
  flake.commonModules.locale =
    { lib, ... }:
    let
      inherit (lib.modules) mkDefault;
    in
    {
      time.timeZone = mkDefault "America/New_York";

      i18n.defaultLocale = mkDefault "en_US.UTF-8";

      console.keyMap = mkDefault "us";
    };
}
