{
  description = "Nix-darwin configuration with mini and develop profiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, nix-homebrew }:
    let
      # Helper function to create darwin configurations
      mkDarwinConfig = { profile, system ? "aarch64-darwin", extraModules ? [] }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            nix-homebrew.darwinModules.nix-homebrew
            ./modules/common.nix
            ./modules/${profile}.nix
          ] ++ extraModules;
        };
    in
    {
      darwinConfigurations = {
        # Mini profile - minimal setup with hostname mini-${serial}
        mini = mkDarwinConfig { profile = "mini"; };

        # Develop profile - extends mini with development tools
        develop = mkDarwinConfig { profile = "develop"; };
      };

      # Expose packages for both architectures
      darwinPackages = {
        aarch64-darwin = self.darwinConfigurations.mini.pkgs;
        x86_64-darwin = self.darwinConfigurations.mini.pkgs;
      };
    };
}
