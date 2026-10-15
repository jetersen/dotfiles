{ pulumi-bin, ... }:
pulumi-bin.overrideAttrs (old: {
  pname = "pulumi-cli";
  # The first source is the official SDK archive; the rest are provider plugins.
  srcs = [ (builtins.head old.srcs) ];
  postUnpack = "";
  installPhase = ''
    rm pulumi-language-* pulumi-resource-* pulumi-watch
  ''
  + old.installPhase;
  meta = old.meta // {
    mainProgram = "pulumi";
    description = "Pulumi CLI without bundled providers or language hosts";
  };
})
