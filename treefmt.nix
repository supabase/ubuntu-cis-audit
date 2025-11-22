{ pkgs, ... }:
{
  # Used to find the project root
  projectRootFile = "flake.nix";

  programs = {
    # Nix formatting
    nixpkgs-fmt.enable = true;

    # Shell formatting
    shellcheck.enable = true;
    shfmt.enable = true;
  };

  settings = {
    global.excludes = [
      "*.min.js"
      "*.lock"
      ".git/**"
      ".direnv/**"
      "result/**"
    ];

    formatter = {
      shellcheck = {
        includes = [ "*.sh" ];
      };

      shfmt = {
        includes = [ "*.sh" ];
        options = [
          "-i"
          "2"
          "-ci"
          "-bn"
        ];
      };
    };
  };
}
