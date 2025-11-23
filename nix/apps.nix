_: {
  perSystem =
    { config, ... }:
    {
      apps = {
        default = {
          type = "app";
          program = "${config.packages.cis-audit}/bin/cis-audit";
        };
        cis-audit = {
          type = "app";
          program = "${config.packages.cis-audit}/bin/cis-audit";
        };
        cis-generate-spec = {
          type = "app";
          program = "${config.packages.cis-generate-spec}/bin/cis-generate-spec";
        };
        ansible-to-goss = {
          type = "app";
          program = "${config.packages.ansible-to-goss}/bin/ansible-to-goss";
        };
      };
    };
}
