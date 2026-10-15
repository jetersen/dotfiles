{ config, lib, ... }:
{
  sops.secrets =
    lib.genAttrs
      [
        "aws-config"
        "kube-config"
        "npm-config"
        "varlock-work-schema"
      ]
      (_: {
        owner = "joseph";
        group = "users";
        mode = "0600";
      })
    // {
      ai-work-instructions = { };
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
