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

          # Tailscale SSH: tailscaled answers SSH over the tailnet itself,
          # authenticating by tailnet identity — no per-device authorized
          # keys. Who may SSH where (and as which user) is governed by the
          # tailnet policy's `ssh` section, not here. Plain sshd still runs
          # and still holds authorized keys as a belt-and-suspenders path
          # (and for non-tailnet access on desktops).
          # `set` flags (unlike `up` flags) are applied by tailscaled-set on
          # every activation, with or without an auth key.
          services.tailscale.extraSetFlags = [ "--ssh" ];

          # Trust the tailnet interface so services bound on it are reachable over
          # Tailscale without opening the public firewall.
          networking.firewall.trustedInterfaces = singleton "tailscale0";
          networking.firewall.checkReversePath = mkDefault "loose";
        })
      ];
    };
}
