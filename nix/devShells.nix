_: {
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        shellHook = config.pre-commit.installationScript;

        buildInputs = with pkgs; [
          # Nix tools
          nil

          # YAML tools
          yamllint
          yq-go

          # Shell tools
          shellcheck
          shfmt

          # SSH for remote operations
          openssh

          # Audit tools
          config.packages.goss
        ];

        packages = [
          config.treefmt.build.wrapper
          config.packages.cis-audit
          config.packages.cis-generate-spec
          config.packages.ansible-to-goss
        ];
      };
    };
}
