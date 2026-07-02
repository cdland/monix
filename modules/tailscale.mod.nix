# Tailscale aspect. Auto-imported into every host but inert until a host sets
# `services.tailscale.enable = true` (and provides an auth key secret).
{
  flake.nixosModules.tailscale =
    { config, lib, ... }:
    let
      inherit (lib.lists) singleton;
      inherit (lib.modules) mkDefault mkIf;
    in
    {
      config = mkIf config.services.tailscale.enable {
        services.tailscale.useRoutingFeatures = mkDefault "client";

        # Trust the tailnet interface so services bound on it are reachable over
        # Tailscale without opening the public firewall.
        networking.firewall.trustedInterfaces = singleton "tailscale0";
        networking.firewall.checkReversePath = mkDefault "loose";
      };
    };
}
