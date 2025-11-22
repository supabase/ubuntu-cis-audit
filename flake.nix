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

        # Script to generate CIS spec from current machine
        cisGenerateSpec = pkgs.writeScriptBin "cis-generate-spec" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          OUTPUT=''${1:-cis-spec.yaml}

          usage() {
            cat << EOF
          CIS Spec Generator

          Generates a CIS specification from the current machine's configuration.
          Run this ON the machine you want to capture as a baseline.

          Usage: cis-generate-spec [output-file]

          Arguments:
            output-file - Output YAML file (default: cis-spec.yaml)

          Example:
            # SSH into your baseline machine first
            ssh admin@baseline-server

            # Then generate the spec
            cis-generate-spec baseline.yaml
          EOF
          }

          if [ "$OUTPUT" = "--help" ] || [ "$OUTPUT" = "-h" ]; then
            usage
            exit 0
          fi

          echo "Generating CIS specification from current machine: $(hostname)"
          echo "Output file: $OUTPUT"
          echo ""

          # Get current system information
          HOSTNAME=$(hostname)
          DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
          OS_INFO=$(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")

          # Get file permissions
          SSHD_MODE=$(stat -c %a /etc/ssh/sshd_config 2>/dev/null || echo "unknown")
          SSHD_OWNER=$(stat -c %U /etc/ssh/sshd_config 2>/dev/null || echo "unknown")
          SSHD_GROUP=$(stat -c %G /etc/ssh/sshd_config 2>/dev/null || echo "unknown")

          PASSWD_MODE=$(stat -c %a /etc/passwd 2>/dev/null || echo "unknown")
          PASSWD_OWNER=$(stat -c %U /etc/passwd 2>/dev/null || echo "unknown")
          PASSWD_GROUP=$(stat -c %G /etc/passwd 2>/dev/null || echo "unknown")

          SHADOW_MODE=$(stat -c %a /etc/shadow 2>/dev/null || echo "unknown")
          SHADOW_OWNER=$(stat -c %U /etc/shadow 2>/dev/null || echo "unknown")
          SHADOW_GROUP=$(stat -c %G /etc/shadow 2>/dev/null || echo "unknown")

          # Check packages
          AIDE_INSTALLED=$(dpkg -l aide 2>/dev/null | grep -q ^ii && echo "true" || echo "false")
          XINETD_INSTALLED=$(dpkg -l xinetd 2>/dev/null | grep -q ^ii && echo "true" || echo "false")
          AUDITD_INSTALLED=$(dpkg -l auditd 2>/dev/null | grep -q ^ii && echo "true" || echo "false")

          # Check services
          UFW_STATUS=$(ufw status 2>/dev/null | grep -q "Status: active" && echo "active" || echo "inactive")

          # Check kernel parameters
          IPV4_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "unknown")
          IPV6_FORWARD=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo "unknown")
          IPV4_SOURCE_ROUTE=$(sysctl -n net.ipv4.conf.all.accept_source_route 2>/dev/null || echo "unknown")
          IPV4_DEFAULT_SOURCE_ROUTE=$(sysctl -n net.ipv4.conf.default.accept_source_route 2>/dev/null || echo "unknown")

          # Generate GOSS YAML
          cat > "$OUTPUT" << EOF
          # CIS Benchmark Specification (GOSS Format)
          # Generated from: $HOSTNAME
          # Date: $DATE
          # OS: $OS_INFO

          file:
            /etc/ssh/sshd_config:
              exists: true
              mode: "$SSHD_MODE"
              owner: $SSHD_OWNER
              group: $SSHD_GROUP
              contains:
          $(grep -E "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | sed 's/^/      - "/' | sed 's/$/"/' || echo '      - "PermitRootLogin no"')
          $(grep -E "^Protocol" /etc/ssh/sshd_config 2>/dev/null | sed 's/^/      - "/' | sed 's/$/"/' || echo '      - "Protocol 2"')

            /etc/passwd:
              exists: true
              mode: "$PASSWD_MODE"
              owner: $PASSWD_OWNER
              group: $PASSWD_GROUP

            /etc/shadow:
              exists: true
              mode: "$SHADOW_MODE"
              owner: $SHADOW_OWNER
              group: $SHADOW_GROUP

            /etc/login.defs:
              exists: true
              contains:
          $(grep -E "^PASS_MIN_LEN" /etc/login.defs 2>/dev/null | sed 's/^/      - "\//' | sed 's/$/\\\s+[0-9]+\/"/' || echo '      - "/PASS_MIN_LEN\\s+14/"')
          $(grep -E "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | sed 's/^/      - "\//' | sed 's/$/\\\s+[0-9]+\/"/' || echo '      - "/PASS_MAX_DAYS\\s+90/"')

          package:
            aide:
              installed: $AIDE_INSTALLED

            xinetd:
              installed: $XINETD_INSTALLED

            auditd:
              installed: $AUDITD_INSTALLED

          service:
            ufw:
              enabled: $([ "$UFW_STATUS" = "active" ] && echo "true" || echo "false")
              running: $([ "$UFW_STATUS" = "active" ] && echo "true" || echo "false")

          kernel-param:
            net.ipv4.ip_forward:
              value: $IPV4_FORWARD

            net.ipv6.conf.all.forwarding:
              value: $IPV6_FORWARD

            net.ipv4.conf.all.accept_source_route:
              value: $IPV4_SOURCE_ROUTE

            net.ipv4.conf.default.accept_source_route:
              value: $IPV4_DEFAULT_SOURCE_ROUTE

          command:
            check-password-fields:
              exec: "awk -F: '(\\\$2 == \"\") {print}' /etc/shadow | wc -l"
              exit-status: 0
              stdout:
                - "0"

            check-ufw-status:
              exec: "ufw status"
              exit-status: 0
              stdout:
                - "/Status: active/"
          EOF

          echo ""
          echo "✓ Specification generated successfully: $OUTPUT"
          echo ""
          echo "Machine details:"
          echo "  Hostname: $HOSTNAME"
          echo "  OS: $OS_INFO"
          echo ""
          echo "Review and edit the specification as needed, then use it for audits."
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
