# LiteLLM proxy aspect. Inert until a host sets `services.litellm.enable`.
# Provides the OpenAI-compatible gateway that Open WebUI talks to.
#
# Bound to localhost; the host supplies model_list and an encrypted
# environmentFile (LITELLM_MASTER_KEY + upstream provider API keys).
{
  flake.nixosModules.litellm =
    { config, lib, ... }:
    let
      inherit (lib.modules) mkDefault mkIf;
    in
    {
      config = mkIf config.services.litellm.enable {
        services.litellm = {
          host = mkDefault "127.0.0.1";
          # 4000 avoids colliding with Open WebUI, which also defaults to 8080.
          port = mkDefault 4000;
          openFirewall = mkDefault false;

          settings.general_settings.master_key = mkDefault "os.environ/LITELLM_MASTER_KEY";
        };
      };
    };
}
