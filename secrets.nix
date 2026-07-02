# agenix rules. Read by the `agenix`/`ragenix` CLI (NOT imported by the flake).
#
# Each entry maps a secret file path (relative to the repo root) to the set of
# public keys it is encrypted to. A host's secrets are encrypted to that host's
# key plus every admin key, so an admin can always rekey them.
#
# To create or edit a secret:    agenix -e hosts/vs0/litellm.env.age
# To rekey everything after a
# key change:                    agenix -r
#
# Add a line here for every new secret before creating it.
let
  keys = import ./keys.nix;

  inherit (keys) admin;
  inherit (keys.hosts) vs0;
in
{
  "hosts/vs0/tailscale.age".publicKeys = [ vs0 ] ++ admin;
  "hosts/vs0/litellm.env.age".publicKeys = [ vs0 ] ++ admin;
  "hosts/vs0/open-webui.env.age".publicKeys = [ vs0 ] ++ admin;
}
