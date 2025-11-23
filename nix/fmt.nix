{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        programs = {
          deadnix.enable = true;
          nixfmt = {
            enable = true;
            package = pkgs.nixfmt-rfc-style;
          };
          shellcheck.enable = true;
          shfmt.enable = true;
        };

        settings.formatter.yamllint = {
          command = pkgs.yamllint;
          options = [
            "-d"
            "{extends: default, rules: {line-length: {max: 120}, document-start: disable, key-duplicates: disable}}"
          ];
          includes = [
            "*.yaml"
            "*.yml"
          ];
        };
      };
    };
}
