# Declares the module-aspect collections used to compose hosts.
#
# `flake.nixosModules` is provided by flake-parts itself. We declare two more as
# mergeable `lazyAttrsOf deferredModule` options so that every `*.mod.nix` file
# can contribute aspects under them and they merge cleanly:
#
#   - commonModules : imported by every host (base options, secrets alias, ...).
#   - homeModules   : Home Manager aspects, applied to the primary user.
{ lib, ... }:
let
  inherit (lib.options) mkOption;
  inherit (lib.types) deferredModule lazyAttrsOf;
in
{
  options.flake.commonModules = mkOption {
    type = lazyAttrsOf deferredModule;
    default = { };
    description = "Modules imported by every host.";
  };

  options.flake.homeModules = mkOption {
    type = lazyAttrsOf deferredModule;
    default = { };
    description = "Home Manager modules applied to the primary user.";
  };
}
