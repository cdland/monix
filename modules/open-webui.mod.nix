# Open WebUI aspect. Inert until a host sets `services.open-webui.enable`.
# Configured to use the local LiteLLM gateway as its OpenAI-compatible backend.
#
# Bound to 0.0.0.0 but NOT opened on the public firewall: reach it over
# Tailscale (the tailscale0 interface is trusted) or via localhost. The host
# supplies an encrypted environmentFile with OPENAI_API_KEY (= the LiteLLM
# master key) and WEBUI_SECRET_KEY.
{
  flake.nixosModules.open-webui =
    { config, lib, ... }:
    let
      inherit (lib.modules) mkDefault mkIf;
    in
    {
      config = mkIf config.services.open-webui.enable {
        services.open-webui = {
          host = mkDefault "0.0.0.0";
          port = mkDefault 8080;
          openFirewall = mkDefault false;

          environment = {
            WEBUI_AUTH = "True";
            ANONYMIZED_TELEMETRY = "False";
            DO_NOT_TRACK = "True";
            SCARF_NO_ANALYTICS = "True";

            ENABLE_OLLAMA_API = "False";
            OPENAI_API_BASE_URL = "http://127.0.0.1:4000/v1";
          };
        };
      };
    };
}
