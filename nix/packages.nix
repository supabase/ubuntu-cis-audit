_: {
  perSystem =
    { pkgs, ... }:
    let

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
        src = ../audit-specs;
        installPhase = ''
          mkdir -p $out/share/cis-audit
          cp -r * $out/share/cis-audit/
        '';
      };

      # Main audit application
      cisAuditApp = pkgs.writeScriptBin "cis-audit" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        SPEC_FILE=""
        LEVEL=""
        PROFILE=""
        OUTPUT_FORMAT="pretty"
        LIST_SPECS=false

        usage() {
          cat << EOF
        CIS Ubuntu Audit Tool

        Usage: cis-audit [OPTIONS]

        Options:
          -s, --spec        Use a specific spec file (e.g., baselines/baseline.yml)
          -l, --level       CIS level 1 or 2 (default: 1)
          -p, --profile     server or workstation (default: server)
          -f, --format      Output format: json, yaml, pretty, tap (default: pretty)
          --list            List all available spec files
          --help            Show this help

        Examples:
          # Use a committed baseline
          cis-audit --spec baselines/baseline.yml

          # Use pre-defined CIS benchmark
          cis-audit --level 1 --profile server

          # List available specs
          cis-audit --list

          # Custom format
          cis-audit --spec baselines/postgres-baseline.yml --format json
        EOF
        }

        # Argument parsing
        while [[ $# -gt 0 ]]; do
          case $1 in
            -s|--spec)
              SPEC_FILE="$2"
              shift 2
              ;;
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
            --list)
              LIST_SPECS=true
              shift
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

        # List specs if requested
        if [ "$LIST_SPECS" = true ]; then
          echo "Available specification files:"
          echo ""
          echo "CIS Benchmarks:"
          find ${cisAuditSpecs}/share/cis-audit -maxdepth 1 -name "cis_*.yaml" -exec basename {} \; | sort
          echo ""
          echo "Baselines:"
          if [ -d "${cisAuditSpecs}/share/cis-audit/baselines" ]; then
            find ${cisAuditSpecs}/share/cis-audit/baselines -name "*.yml" -o -name "*.yaml" | while read f; do
              basename "$f"
            done | sort
          fi
          exit 0
        fi

        # Determine which spec file to use
        if [ -n "$SPEC_FILE" ]; then
          # Use specified spec (support both full path and relative)
          if [[ "$SPEC_FILE" = /* ]]; then
            FULL_SPEC_PATH="$SPEC_FILE"
          else
            FULL_SPEC_PATH="${cisAuditSpecs}/share/cis-audit/$SPEC_FILE"
          fi
        else
          # Use level/profile (default to level 1 server)
          LEVEL=''${LEVEL:-1}
          PROFILE=''${PROFILE:-server}
          FULL_SPEC_PATH="${cisAuditSpecs}/share/cis-audit/cis_level''${LEVEL}_''${PROFILE}.yaml"
        fi

        if [[ ! -f "$FULL_SPEC_PATH" ]]; then
          echo "Error: Spec file not found: $FULL_SPEC_PATH"
          echo ""
          echo "Run 'cis-audit --list' to see available specs"
          exit 1
        fi

        echo "Running audit with: $(basename $FULL_SPEC_PATH)"
        echo ""

        # Run GOSS with sudo
        sudo ${goss}/bin/goss --gossfile "$FULL_SPEC_PATH" validate --format "$OUTPUT_FORMAT"
      '';

      # Script to generate comprehensive machine baseline spec
      cisGenerateSpec = pkgs.writeScriptBin "cis-generate-spec" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        OUTPUT=''${1:-machine-baseline.yaml}

        usage() {
          cat << EOF
        Comprehensive Machine Baseline Generator

        Generates a complete GOSS specification capturing the entire machine state.
        Run this ON the machine you want to capture as a baseline.

        Captures:
          - ALL installed packages
          - ALL systemd services (state)
          - ALL kernel parameters
          - ALL critical file permissions (/etc)
          - ALL user accounts
          - ALL groups
          - Network configuration
          - Listening ports

        Usage: cis-generate-spec [output-file]

        Arguments:
          output-file - Output YAML file (default: machine-baseline.yaml)

        Example:
          # SSH into your baseline machine
          ssh admin@baseline-server

          # Generate complete baseline
          sudo cis-generate-spec baseline.yaml

        Note: Requires sudo for complete system access
        EOF
        }

        if [ "$OUTPUT" = "--help" ] || [ "$OUTPUT" = "-h" ]; then
          usage
          exit 0
        fi

        echo "=================================================="
        echo "Comprehensive Machine Baseline Generator"
        echo "=================================================="
        echo ""
        echo "Hostname: $(hostname)"
        echo "Output: $OUTPUT"
        echo ""
        echo "Capturing complete machine state..."
        echo "This may take a few minutes..."
        echo ""

        # Temp file for building the spec
        TMPFILE=$(mktemp)

        # Header
        cat > "$TMPFILE" << 'HEADER'
        # Complete Machine Baseline Specification (GOSS Format)
        # Generated by: cis-generate-spec
        HEADER

        echo "# Hostname: $(hostname)" >> "$TMPFILE"
        echo "# Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$TMPFILE"
        echo "# OS: $(lsb_release -d 2>/dev/null | cut -f2 || uname -a)" >> "$TMPFILE"
        echo "# Kernel: $(uname -r)" >> "$TMPFILE"
        echo "" >> "$TMPFILE"

        # ===== PACKAGES =====
        echo "[1/8] Capturing all installed packages..."
        echo "package:" >> "$TMPFILE"

        dpkg -l 2>/dev/null | grep ^ii | awk '{print $2}' | while read -r pkg; do
          version=$(dpkg -l "$pkg" 2>/dev/null | grep ^ii | awk '{print $3}')
          echo "  $pkg:" >> "$TMPFILE"
          echo "    installed: true" >> "$TMPFILE"
          echo "    versions:" >> "$TMPFILE"
          echo "      - $version" >> "$TMPFILE"
        done

        # ===== SERVICES =====
        echo "[2/8] Capturing all systemd services..."
        echo "" >> "$TMPFILE"
        echo "service:" >> "$TMPFILE"

        systemctl list-unit-files --type=service 2>/dev/null | grep -E '\.(service)' | while read -r line; do
          service=$(echo "$line" | awk '{print $1}' | sed 's/\.service$//')
          state=$(echo "$line" | awk '{print $2}')

          # Check if running
          if systemctl is-active "$service" &>/dev/null; then
            running="true"
          else
            running="false"
          fi

          # Check if enabled
          if systemctl is-enabled "$service" &>/dev/null; then
            enabled="true"
          else
            enabled="false"
          fi

          echo "  $service:" >> "$TMPFILE"
          echo "    enabled: $enabled" >> "$TMPFILE"
          echo "    running: $running" >> "$TMPFILE"
        done

        # ===== KERNEL PARAMETERS =====
        echo "[3/8] Capturing all kernel parameters..."
        echo "" >> "$TMPFILE"
        echo "kernel-param:" >> "$TMPFILE"

        sysctl -a 2>/dev/null | while IFS='=' read -r key value; do
          key=$(echo "$key" | xargs)
          value=$(echo "$value" | xargs)
          echo "  $key:" >> "$TMPFILE"
          echo "    value: \"$value\"" >> "$TMPFILE"
        done

        # ===== FILES =====
        echo "[4/8] Capturing critical file permissions..."
        echo "" >> "$TMPFILE"
        echo "file:" >> "$TMPFILE"

        # List of critical directories and files
        for path in /etc /etc/ssh /etc/pam.d /etc/security /boot /root; do
          if [ -d "$path" ]; then
            find "$path" -maxdepth 2 -type f 2>/dev/null | while read -r file; do
              if [ -f "$file" ]; then
                mode=$(stat -c %a "$file" 2>/dev/null || echo "unknown")
                owner=$(stat -c %U "$file" 2>/dev/null || echo "unknown")
                group=$(stat -c %G "$file" 2>/dev/null || echo "unknown")

                # Use relative path from /
                echo "  $file:" >> "$TMPFILE"
                echo "    exists: true" >> "$TMPFILE"
                echo "    mode: \"$mode\"" >> "$TMPFILE"
                echo "    owner: $owner" >> "$TMPFILE"
                echo "    group: $group" >> "$TMPFILE"
              fi
            done
          fi
        done

        # ===== USERS =====
        echo "[5/8] Capturing all user accounts..."
        echo "" >> "$TMPFILE"
        echo "user:" >> "$TMPFILE"

        while IFS=: read -r username _ uid gid _ homedir shell; do
          echo "  $username:" >> "$TMPFILE"
          echo "    exists: true" >> "$TMPFILE"
          echo "    uid: $uid" >> "$TMPFILE"
          echo "    gid: $gid" >> "$TMPFILE"
          echo "    home: $homedir" >> "$TMPFILE"
          echo "    shell: $shell" >> "$TMPFILE"
        done < /etc/passwd

        # ===== GROUPS =====
        echo "[6/8] Capturing all groups..."
        echo "" >> "$TMPFILE"
        echo "group:" >> "$TMPFILE"

        while IFS=: read -r groupname _ gid members; do
          echo "  $groupname:" >> "$TMPFILE"
          echo "    exists: true" >> "$TMPFILE"
          echo "    gid: $gid" >> "$TMPFILE"
        done < /etc/group

        # ===== PORTS =====
        echo "[7/8] Capturing listening ports..."
        echo "" >> "$TMPFILE"
        echo "port:" >> "$TMPFILE"

        ss -tulpn 2>/dev/null | grep LISTEN | awk '{print $5}' | sed 's/.*://' | sort -u | while read -r port; do
          if [ -n "$port" ] && [ "$port" != "0" ]; then
            echo "  tcp:$port:" >> "$TMPFILE"
            echo "    listening: true" >> "$TMPFILE"
          fi
        done

        # ===== COMMANDS (for dynamic checks) =====
        echo "[8/8] Adding verification commands..."
        echo "" >> "$TMPFILE"
        echo "command:" >> "$TMPFILE"

        # Password policy check
        echo "  empty-passwords:" >> "$TMPFILE"
        echo "    exec: \"awk -F: '(\\\$2 == \\\"\\\") {print}' /etc/shadow | wc -l\"" >> "$TMPFILE"
        echo "    exit-status: 0" >> "$TMPFILE"
        echo "    stdout:" >> "$TMPFILE"
        echo "      - \"0\"" >> "$TMPFILE"

        # Move temp file to output
        mv "$TMPFILE" "$OUTPUT"

        echo ""
        echo "=================================================="
        echo "✓ Complete baseline captured successfully!"
        echo "=================================================="
        echo ""
        echo "Output file: $OUTPUT"
        echo "Machine: $(hostname)"
        echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || uname -a)"
        echo ""
        echo "Statistics:"
        echo "  Packages: $(grep -c 'installed: true' "$OUTPUT" || echo 0)"
        echo "  Services: $(grep -c 'enabled:' "$OUTPUT" || echo 0)"
        echo "  Files: $(grep -c 'exists: true' "$OUTPUT" || echo 0)"
        echo "  Users: $(wc -l < /etc/passwd)"
        echo "  Groups: $(wc -l < /etc/group)"
        echo ""
        echo "Use this baseline to audit other machines with:"
        echo "  goss --gossfile $OUTPUT validate"
      '';

      # Script to convert Ansible playbooks to GOSS specs
      ansibleToGoss = pkgs.writeScriptBin "ansible-to-goss" ''
        #!${pkgs.python3}/bin/python3
        import yaml
        import sys
        import os
        from pathlib import Path

        def usage():
            print("""
        Ansible to GOSS Converter

        Converts Ansible playbooks and tasks to GOSS specifications.

        Usage: ansible-to-goss <ansible-playbook-dir> [output-file]

        Arguments:
          ansible-playbook-dir - Path to Ansible playbook directory
          output-file         - Output YAML file (default: ansible-baseline.yaml)

        Example:
          ansible-to-goss ./ansible baseline.yaml
          ansible-to-goss /Users/samrose/postgres-dev/ansible
        """)

        def parse_ansible_apt(task):
            """Convert Ansible apt tasks to GOSS package specs"""
            packages = []
            if "pkg" in task.get("ansible.builtin.apt", {}):
                pkgs = task["ansible.builtin.apt"]["pkg"]
                if isinstance(pkgs, list):
                    packages = pkgs
                elif isinstance(pkgs, str):
                    packages = [pkgs]
            elif "name" in task.get("ansible.builtin.apt", {}):
                packages = [task["ansible.builtin.apt"]["name"]]
            elif "pkg" in task.get("apt", {}):
                pkgs = task["apt"]["pkg"]
                if isinstance(pkgs, list):
                    packages = pkgs
                elif isinstance(pkgs, str):
                    packages = [pkgs]
            return packages

        def parse_ansible_sysctl(task):
            """Convert Ansible sysctl tasks to GOSS kernel-param specs"""
            params = {}
            for module in ["ansible.builtin.sysctl", "ansible.posix.sysctl", "sysctl"]:
                if module in task:
                    name = task[module].get("name")
                    value = task[module].get("value")
                    if name and value is not None:
                        params[name] = str(value)
            return params

        def parse_ansible_systemd(task):
            """Convert Ansible systemd tasks to GOSS service specs"""
            services = {}
            for module in ["ansible.builtin.systemd_service", "ansible.builtin.systemd", "systemd"]:
                if module in task:
                    name = task[module].get("name", "").replace(".service", "")
                    state = task[module].get("state", "")
                    enabled = task[module].get("enabled", None)

                    if name:
                        service_spec = {}
                        if enabled is not None:
                            service_spec["enabled"] = enabled
                        if state in ["started", "restarted"]:
                            service_spec["running"] = True
                        elif state == "stopped":
                            service_spec["running"] = False

                        if service_spec:
                            services[name] = service_spec
            return services

        def parse_ansible_file(task):
            """Convert Ansible file/copy tasks to GOSS file specs"""
            files = {}
            for module in ["ansible.builtin.file", "ansible.builtin.copy", "file", "copy"]:
                if module in task:
                    path = task[module].get("dest") or task[module].get("path")
                    if path:
                        file_spec = {"exists": True}

                        if "mode" in task[module]:
                            mode = task[module]["mode"]
                            if isinstance(mode, str):
                                mode = mode.strip("'\"")
                            file_spec["mode"] = str(mode)

                        if "owner" in task[module]:
                            file_spec["owner"] = task[module]["owner"]

                        if "group" in task[module]:
                            file_spec["group"] = task[module]["group"]

                        files[path] = file_spec
            return files

        def convert_ansible_to_goss(ansible_dir):
            """Main conversion function"""
            goss_spec = {
                "package": {},
                "service": {},
                "kernel-param": {},
                "file": {},
                "command": {}
            }

            # Find all YAML files
            ansible_path = Path(ansible_dir)
            yaml_files = list(ansible_path.glob("**/*.yml")) + list(ansible_path.glob("**/*.yaml"))

            print(f"[*] Found {len(yaml_files)} Ansible files")
            print(f"[*] Processing...")

            for yaml_file in yaml_files:
                try:
                    with open(yaml_file, "r") as f:
                        data = yaml.safe_load(f)

                        if not data:
                            continue

                        # Handle playbooks (list of plays)
                        if isinstance(data, list):
                            for play in data:
                                if isinstance(play, dict) and "tasks" in play:
                                    for task in play["tasks"]:
                                        process_task(task, goss_spec)
                                elif isinstance(play, dict):
                                    # Direct task
                                    process_task(play, goss_spec)

                        # Handle task files
                        elif isinstance(data, dict):
                            process_task(data, goss_spec)

                except Exception as e:
                    print(f"[!] Warning: Failed to parse {yaml_file}: {e}", file=sys.stderr)
                    continue

            # Remove empty sections
            return {k: v for k, v in goss_spec.items() if v}

        def process_task(task, goss_spec):
            """Process a single Ansible task"""
            if not isinstance(task, dict):
                return

            # Extract packages from apt tasks
            packages = parse_ansible_apt(task)
            for pkg in packages:
                goss_spec["package"][pkg] = {"installed": True}

            # Extract sysctl params
            params = parse_ansible_sysctl(task)
            for name, value in params.items():
                goss_spec["kernel-param"][name] = {"value": value}

            # Extract services
            services = parse_ansible_systemd(task)
            for name, spec in services.items():
                if name not in goss_spec["service"]:
                    goss_spec["service"][name] = {}
                goss_spec["service"][name].update(spec)

            # Extract files
            files = parse_ansible_file(task)
            for path, spec in files.items():
                goss_spec["file"][path] = spec

        def main():
            if len(sys.argv) < 2 or sys.argv[1] in ["-h", "--help"]:
                usage()
                sys.exit(0 if len(sys.argv) >= 2 else 1)

            ansible_dir = sys.argv[1]
            output_file = sys.argv[2] if len(sys.argv) > 2 else "ansible-baseline.yaml"

            if not os.path.isdir(ansible_dir):
                print(f"Error: Directory not found: {ansible_dir}", file=sys.stderr)
                sys.exit(1)

            print("=" * 60)
            print("Ansible to GOSS Converter")
            print("=" * 60)
            print()
            print(f"Input:  {ansible_dir}")
            print(f"Output: {output_file}")
            print()

            goss_spec = convert_ansible_to_goss(ansible_dir)

            # Add header comments
            header = f"""# GOSS Specification
        # Generated from Ansible playbooks in: {ansible_dir}
        # DO NOT EDIT - Generated by ansible-to-goss

        """

            with open(output_file, "w") as f:
                f.write(header)
                yaml.dump(goss_spec, f, default_flow_style=False, sort_keys=False)

            print()
            print("=" * 60)
            print("✓ Conversion complete!")
            print("=" * 60)
            print()
            print("Statistics:")
            print(f"  Packages: {len(goss_spec.get(\"package\", {}))}")
            print(f"  Services: {len(goss_spec.get(\"service\", {}))}")
            print(f"  Kernel params: {len(goss_spec.get(\"kernel-param\", {}))}")
            print(f"  Files: {len(goss_spec.get(\"file\", {}))}")
            print()
            print(f"Output: {output_file}")
            print()
            print("Review and edit the spec, then use it with:")
            print(f"  goss --gossfile {output_file} validate")

        if __name__ == "__main__":
            main()
      '';
    in
    {
      packages = {
        default = cisAuditApp;
        cis-audit = cisAuditApp;
        cis-generate-spec = cisGenerateSpec;
        ansible-to-goss = ansibleToGoss;
        goss = goss;
        specs = cisAuditSpecs;
      };
    };
}
