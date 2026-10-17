{ config, lib, ... }:
let
  schema = builtins.fromJSON (builtins.readFile ../secrets/work-schema.json);
in
{
  sops.secrets =
    lib.genAttrs
      schema.userSecrets
      (_: {
        sopsFile = ../secrets/work.yaml;
        owner = "joseph";
        group = "users";
        mode = "0600";
      })
    // {
      "${schema.aiSecret}".sopsFile = ../secrets/work.yaml;
    };
  sops.templates.ai-instructions = {
    owner = "joseph";
    group = "users";
    mode = "0600";
    content =
      lib.replaceStrings [ "@AI_WORK_INSTRUCTIONS@" ] [ config.sops.placeholder.ai-work-instructions ]
        (builtins.readFile ../../home/.chezmoitemplates/ai-instructions.md);
  };
}
