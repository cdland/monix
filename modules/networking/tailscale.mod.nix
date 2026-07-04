# Tailscale aspect. Auto-imported into every host and enabled by default.
# Opt out per host with `services.tailscale.enable = lib.modules.mkForce false;`.
{
  flake.nixosModules.tailscale =
    { config, lib, ... }:
    let
      inherit (lib.lists) singleton;
      inherit (lib.modules) mkDefault mkIf mkMerge;
    in
    {
      config = mkMerge [
        # Universal: every host runs tailscale. Opt out per host with
        # `services.tailscale.enable = lib.modules.mkForce false;`.
        { services.tailscale.enable = mkDefault true; }
        (mkIf config.services.tailscale.enable {
          services.tailscale.useRoutingFeatures = mkDefault "client";

          # Trust the tailnet interface so services bound on it are reachable over
          # Tailscale without opening the public firewall.
          networking.firewall.trustedInterfaces = singleton "tailscale0";
          networking.firewall.checkReversePath = mkDefault "loose";
        })
      ];
    };
}
