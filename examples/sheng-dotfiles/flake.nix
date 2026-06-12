{
  description = "Personal configuration for a Xiaomi Pad 6S Pro running Mobile NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xiaomi-sheng.url = "github:DotRedstone/nixos-xiaomi-sheng?dir=nixos";
  };

  outputs = { nixpkgs, home-manager, xiaomi-sheng, ... }@inputs:
    let
      system = "aarch64-linux";
    in
    {
      nixosConfigurations.sheng =
        xiaomi-sheng.lib.${system}.mkShengSystem [
          { _module.args.inputs = inputs; }
          ./hosts/sheng/configuration.nix
        ];

      homeConfigurations."user@sheng" =
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit inputs; };
          modules = [ ./home/user.nix ];
        };
    };
}
