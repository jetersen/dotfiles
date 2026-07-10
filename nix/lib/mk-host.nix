{ inputs }:
{
  hostSpec,
  modules ? [ ],
  homeModules ? [ ],
}:
inputs.nixpkgs.lib.nixosSystem {
  system = hostSpec.system;

  specialArgs = {
    inherit inputs hostSpec;
  };

  modules = [
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager
    ../modules/nixos/core.nix

    ({ ... }: {
      networking.hostName = hostSpec.hostName;

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "hm-backup";
        extraSpecialArgs = {
          inherit inputs hostSpec;
        };
        users.joseph.imports = [ ../modules/home/common.nix ] ++ homeModules;
      };
    })
  ]
  ++ modules;
}
