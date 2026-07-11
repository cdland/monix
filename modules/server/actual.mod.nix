# Actual Budget aspect — the family budgeting app (spending, categories,
# balances, net-worth reports), served by the upstream `services.actual`
# NixOS module. Inert until a host sets `actual.enable` (same pattern as
# minecraft.mod.nix / inference.mod.nix).
#
# ACCESS MODEL. Two front doors, no public port of its own:
#   - tailnet: the service listens on all interfaces with openFirewall =
#     false, so on fw0 only the trusted tailscale0 interface reaches it
#     directly (the minecraft/llama-swap reachability pattern).
#   - web: Cloudflare Tunnel -> http://127.0.0.1:<port>, with per-person
#     family logins enforced by Cloudflare Access — the ai.su.is pattern.
#     Both the public hostname (budget.<domain> -> the local port) and the
#     Access application/policy live in the Zero Trust DASHBOARD, not here;
#     the existing cockpit tunnel connector carries the extra hostname.
# Actual's own server password remains enabled underneath as a second
# factor of sorts; Access is the real authentication layer.
#
# THREAT MODEL. A Node web app holding family financial data, reachable
# from the public internet through Access. Assume compromise is possible
# and make it lead nowhere: the upstream module already runs it
# DynamicUser in a strict sandbox (ProtectSystem=strict, empty caps,
# @system-service filter, StateDirectory the sole writable path); we add
# the services.slice fence and the house anti-pivot egress fence. The
# fence also denies ALL public egress, which deliberately breaks Actual's
# optional bank-sync integrations (GoCardless/SimpleFIN) — this is a
# manual-entry instance; open a named pinhole if bank sync is ever wanted.
#
# DATA. Everything lives in /var/lib/actual (SQLite + user files),
# root-and-service-only (StateDirectoryMode 0700). Small, cold, and
# precious — include it when the off-host backup solution (pending, see
# the Minecraft world backup project) is designed.
{
  flake.nixosModules.actual =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib.meta) getExe;
      inherit (lib.modules) mkIf;
      inherit (lib.options) mkEnableOption mkOption;
      inherit (lib) types;

      cfg = config.actual;
    in
    {
      options.actual = {
        enable = mkEnableOption "the tailnet+Cloudflare-Access Actual Budget server";

        port = mkOption {
          type = types.port;
          default = 5006;
          description = ''
            Listen port (Actual's upstream default; the nixpkgs module
            defaults to 3000, which clashes with common dev servers).
            The Cloudflare public hostname must target this port.
          '';
        };

        tunnelTokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            Cloudflare Tunnel connector token for the budget hostname;
            null = tailnet-only, no public web access. This is Actual's OWN
            tunnel (not the opencode cockpit's), so the budget app's public
            ingress can be revoked independently of the cockpit seat. The
            public hostname -> http://127.0.0.1:<port> mapping and the
            Access application guarding it are managed in Cloudflare Zero
            Trust, not here.
          '';
        };
      };

      config = mkIf cfg.enable {
        services.actual = {
          enable = true;
          # No public inbound port; see the access-model header.
          openFirewall = false;
          settings = {
            inherit (cfg) port;
            # Bind everywhere; reachability is the firewall's job (the fw0
            # pattern): tailscale0 is trusted, loopback serves cloudflared.
            hostname = "::";
            # Cloudflare terminates TLS and proxies over loopback; trust
            # loopback so Actual sees real client IPs from CF headers
            # instead of rate-limiting everyone as 127.0.0.1.
            trustedProxies = [ "127.0.0.1/32" ];
          };
        };

        systemd.services.actual.serviceConfig = {
          # Count it against the general services fence alongside Minecraft,
          # not the default system slice.
          Slice = "services.slice";

          # Anti-pivot egress fence (cf. minecraft.mod.nix, but tighter: no
          # public internet at all — nothing this instance needs is outside
          # the machine). Loopback carries the cloudflared hop; the tailnet
          # carries direct family clients. Everything else, both directions,
          # is denied — a compromised app can't reach the LAN, the fleet
          # bridge, or an exfil endpoint.
          IPAddressAllow = [
            "127.0.0.0/8"
            "::1"
            "100.64.0.0/10" # tailnet (CGNAT range)
          ];
          IPAddressDeny = "any";
        };

        # Public web ingress: a dedicated cloudflared connector (cf. the
        # opencode-web-tunnel in cockpit.mod.nix). It dials OUT to
        # Cloudflare's edge and proxies the dashboard-configured hostname to
        # Actual over loopback — no inbound port. Cloudflare Access in front
        # is the authentication layer; Actual's server password sits under it.
        systemd.services.actual-tunnel = mkIf (cfg.tunnelTokenFile != null) {
          description = "Cloudflare Tunnel for Actual Budget";
          wantedBy = [ "multi-user.target" ];
          partOf = [ "actual.service" ];
          wants = [
            "network-online.target"
            "actual.service"
          ];
          after = [
            "network-online.target"
            "actual.service"
          ];
          serviceConfig = {
            DynamicUser = true;
            LoadCredential = [ "token:${cfg.tunnelTokenFile}" ];
            ExecStart = "${getExe pkgs.cloudflared} tunnel --no-autoupdate run --token-file %d/token";
            Restart = "always";
            RestartSec = 5;
          };
          environment = {
            TUNNEL_TRANSPORT_PROTOCOL = "http2";
          };
        };
      };
    };
}
