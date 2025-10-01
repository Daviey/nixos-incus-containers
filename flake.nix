{
  description = "Incus container management flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = import ./lib.nix { inherit nixpkgs; };
    in {
      nixosModules.incus-container = import ./modules/incus-container.nix;

      lib = lib;

      nixosConfigurations = {
        # Example configuration - users can override or extend
        example-container = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.incus-container
            {
              incus.container.enable = true;
              networking.hostName = "example-container";
            }
          ];
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.incus pkgs.git pkgs.nixfmt-rfc-style ];
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;

      apps.${system} = lib.makeHelperApps {
        inherit pkgs;
        containerName = "example-container";
        flakeOutPath = self.outPath;
      };
    };
}
