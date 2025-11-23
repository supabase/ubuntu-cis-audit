{
  description = "CIS Ubuntu Audit Tool - Run locally on target machine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
      ];

      imports = [
        ./nix/fmt.nix
        ./nix/hooks.nix
        ./nix/packages.nix
        ./nix/apps.nix
        ./nix/devShells.nix
        ./nix/checks.nix
      ];
    };
}
