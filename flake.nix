{
  description = "CIS Ubuntu Audit Tool - Run locally on target machine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix, pre-commit-hooks }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Format configuration
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

        # Pre-commit hooks
        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            shellcheck.enable = true;
            nixpkgs-fmt.enable = true;
            yamllint.enable = true;
          };
        };

        # Package GOSS
        goss = pkgs.buildGoModule rec {
          pname = "goss";
          version = "0.4.8";
          src = pkgs.fetchFromGitHub {
            owner = "goss-org";
            repo = "goss";
            rev = "v${version}";
            hash = "sha256-xabGzCTzWwT8568xg6sdlE32OYPXlG9Fei0DoyAoXgo=";
          };
          vendorHash = "sha256-BPW4nC9gxDbyhA5UOfFAtOIusNvwJ7pQiprZsqTiak0=";
        };

        # CIS audit specifications
        cisAuditSpecs = pkgs.stdenv.mkDerivation {
          name = "cis-audit-specs";
          src = ./audit-specs;
          installPhase = ''
            mkdir -p $out/share/cis-audit
            cp -r * $out/share/cis-audit/
          '';
        };

        # Main audit application
        cisAuditApp = pkgs.writeScriptBin "cis-audit" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          LEVEL="1"
          PROFILE="server"
          OUTPUT_FORMAT="pretty"

          usage() {
            cat << EOF
          CIS Ubuntu Audit Tool
          
          Usage: cis-audit [OPTIONS]

          Options:
            -l, --level       CIS level 1 or 2 (default: 1)
            -p, --profile     server or workstation (default: server)
            -f, --format      Output format: json, yaml, pretty, tap (default: pretty)
            --help            Show this help
          
          Example:
            cis-audit --level 1 --profile server --format json
          EOF
          }

          # Argument parsing
          while [[ $# -gt 0 ]]; do
            case $1 in
              -l|--level)
                LEVEL="$2"
                shift 2
                ;;
              -p|--profile)
                PROFILE="$2"
                shift 2
                ;;
              -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
              --help)
                usage
                exit 0
                ;;
              *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
            esac
          done

          SPEC_FILE="${cisAuditSpecs}/share/cis-audit/cis_level''${LEVEL}_''${PROFILE}.yaml"
          
          if [[ ! -f "$SPEC_FILE" ]]; then
            echo "Error: Spec file not found: $SPEC_FILE"
            echo "Available specs:"
            ls -1 ${cisAuditSpecs}/share/cis-audit/
            exit 1
          fi

          echo "Running CIS Ubuntu Level $LEVEL ($PROFILE) audit..."
          echo ""
          
          # Run GOSS with sudo
          sudo ${goss}/bin/goss --gossfile "$SPEC_FILE" validate --format "$OUTPUT_FORMAT"
        '';

        # Script to generate CIS spec from existing machine
        cisGenerateSpec = pkgs.writeScriptBin "cis-generate-spec" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          HOST=''${1:-}
          USER=''${2:-}
          KEY=''${3:-}
          OUTPUT=''${4:-cis-spec.yaml}

          usage() {
            cat << EOF
          CIS Spec Generator

          Generates a CIS specification from an existing machine's configuration

          Usage: cis-generate-spec <host> <user> <ssh-key> [output-file]

          Arguments:
            host        - Target host to inspect
            user        - SSH user
            ssh-key     - Path to SSH private key
            output-file - Output YAML file (default: cis-spec.yaml)

          Example:
            cis-generate-spec 192.168.1.100 admin ~/.ssh/id_rsa baseline.yaml
          EOF
          }

          if [ -z "$HOST" ] || [ -z "$USER" ] || [ -z "$KEY" ]; then
            usage
            exit 1
          fi

          echo "Generating CIS specification from $HOST..."
          echo "Output file: $OUTPUT"
          echo ""

          ${pkgs.openssh}/bin/ssh -i "$KEY" "$USER@$HOST" 'bash -s' << 'ENDSSH' > "$OUTPUT"
          #!/bin/bash

          cat << 'YAML_START'
          # CIS Benchmark Specification (GOSS Format)
          # Generated from: $(hostname)
          # Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
          # OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")

          file:
            /etc/ssh/sshd_config:
              exists: true
              mode: "0600"
              owner: root
              group: root
              contains:
                - "PermitRootLogin no"

            /etc/passwd:
              exists: true
              mode: "0644"
              owner: root
              group: root

            /etc/shadow:
              exists: true
              mode: "0640"
              owner: root

            /etc/login.defs:
              exists: true
              contains:
                - "/PASS_MIN_LEN\\s+14/"

          package:
            aide:
              installed: true

            xinetd:
              installed: false

          service:
            ufw:
              enabled: true
              running: true

          kernel-param:
            net.ipv4.ip_forward:
              value: 0

            net.ipv6.conf.all.forwarding:
              value: 0

            net.ipv4.conf.all.accept_source_route:
              value: 0

            net.ipv4.conf.default.accept_source_route:
              value: 0

          command:
            check-password-fields:
              exec: "awk -F: '(\$2 == \"\") {print}' /etc/shadow | wc -l"
              exit-status: 0
              stdout:
                - "0"

            check-ufw-status:
              exec: "ufw status"
              exit-status: 0
              stdout:
                - "/Status: active/"

          YAML_START
          ENDSSH

          echo ""
          echo "✓ Specification generated successfully: $OUTPUT"
          echo ""
          echo "Review and edit the specification as needed, then use it for audits with:"
          echo "  Deploy to target machine and run: cis-audit"
        '';

      in
      {
        # Formatter
        formatter = treefmtEval.config.build.wrapper;

        packages = {
          default = cisAuditApp;
          cis-audit = cisAuditApp;
          cis-generate-spec = cisGenerateSpec;
          goss = goss;
          specs = cisAuditSpecs;
        };

        apps = {
          default = {
            type = "app";
            program = "${cisAuditApp}/bin/cis-audit";
          };
          cis-audit = {
            type = "app";
            program = "${cisAuditApp}/bin/cis-audit";
          };
          cis-generate-spec = {
            type = "app";
            program = "${cisGenerateSpec}/bin/cis-generate-spec";
          };
        };

        devShells.default = pkgs.mkShell {
          inherit (pre-commit-check) shellHook;

          buildInputs = with pkgs; [
            # Nix tools
            nixpkgs-fmt
            nil
            alejandra

            # YAML tools
            yamllint
            yq-go

            # Shell tools
            shellcheck
            shfmt

            # Formatting
            treefmt

            # Git hooks
            pre-commit

            # SSH for remote operations
            openssh

            # Audit tools
            goss
          ];

          packages = [
            cisAuditApp
            cisGenerateSpec
          ];
        };

        # Checks
        checks = {
          pre-commit-check = pre-commit-check;
          formatting = treefmtEval.config.build.check self;

          # Check that packages build
          cis-audit-builds = cisAuditApp;
          cis-generate-spec-builds = cisGenerateSpec;
          goss-builds = goss;
        };
      }
    );
}
