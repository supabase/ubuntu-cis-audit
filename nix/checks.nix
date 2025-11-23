_: {
  perSystem =
    { config, ... }:
    {
      checks = {
        # Check that packages build
        cis-audit-builds = config.packages.cis-audit;
        cis-generate-spec-builds = config.packages.cis-generate-spec;
        ansible-to-goss-builds = config.packages.ansible-to-goss;
        goss-builds = config.packages.goss;
      };
    };
}
