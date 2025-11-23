# Ubuntu CIS Audit Toolkit

A comprehensive security auditing toolkit for Ubuntu systems using [GOSS](https://github.com/goss-org/goss) and Nix.

## Features

**Three Powerful Tools:**
- **`cis-generate-spec`** - Capture complete machine baseline (packages, services, configs, etc.)
- **`ansible-to-goss`** - Convert Ansible playbooks to GOSS specifications
- **`cis-audit`** - Validate machines against CIS benchmarks or custom baselines

**Use Cases:**
- Audit Ubuntu servers against CIS benchmarks
- Create baselines from "golden" machines
- Validate infrastructure-as-code compliance
- Continuous compliance monitoring

## Quick Start

### List Available Specs
```bash
nix run github:supabase/ubuntu-cis-audit#cis-audit -- --list
```

### Audit Against Bundled Baseline
```bash
# Using committed baseline
sudo nix run github:supabase/ubuntu-cis-audit#cis-audit -- --spec baselines/baseline.yml

# Using CIS benchmark
sudo nix run github:supabase/ubuntu-cis-audit#cis-audit -- --level 1 --profile server
```

### Generate Machine Baseline
```bash
# Capture complete system state
sudo nix run github:supabase/ubuntu-cis-audit#cis-generate-spec -- my-baseline.yaml
```

### Convert Ansible to GOSS
```bash
# Convert Ansible playbooks to GOSS spec
nix run github:supabase/ubuntu-cis-audit#ansible-to-goss ./ansible baseline.yaml
```

## Installation

### Development Environment
```bash
git clone https://github.com/supabase/ubuntu-cis-audit
cd ubuntu-cis-audit
nix develop
```

This gives you access to:
- All audit tools (`cis-audit`, `cis-generate-spec`, `ansible-to-goss`)
- GOSS binary
- Development tools (yamllint, shellcheck, nixpkgs-fmt)

## Usage

### cis-audit

Validate a machine against CIS benchmarks or custom baselines.

```bash
# Use bundled baseline
sudo cis-audit --spec baselines/postgres-baseline.yml

# Use CIS benchmark
sudo cis-audit --level 1 --profile server

# JSON output
sudo cis-audit --spec baselines/baseline.yml --format json

# List available specs
cis-audit --list
```

**Options:**
- `-s, --spec <file>` - Use specific spec file from bundled specs
- `-l, --level <1|2>` - CIS benchmark level
- `-p, --profile <server|workstation>` - System profile
- `-f, --format <pretty|json|yaml|tap>` - Output format
- `--list` - List all available specifications

### cis-generate-spec

Generate a comprehensive baseline from a running machine.

```bash
# Capture complete system state
sudo cis-generate-spec baseline.yaml
```

**Captures:**
- All installed packages (with versions)
- All systemd services (enabled/running state)
- All kernel parameters (sysctl)
- Critical file permissions
- All user accounts and groups
- Listening network ports
- System metadata

**Requirements:** Must run with `sudo` to access protected files.

### ansible-to-goss

Convert Ansible playbooks to GOSS specifications.

```bash
# Convert Ansible directory to GOSS spec
ansible-to-goss ./ansible-playbooks output.yaml
```

**Extracts:**
- `apt` tasks → `package:` specs
- `sysctl` tasks → `kernel-param:` specs
- `systemd` tasks → `service:` specs
- `file/copy` tasks → `file:` specs

## Workflow Examples

### Baseline-Driven Compliance

1. **Generate baseline from golden machine:**
```bash
ssh admin@golden-server
sudo nix run github:supabase/ubuntu-cis-audit#cis-generate-spec -- baseline.yaml
```

2. **Commit baseline to repo:**
```bash
cp baseline.yaml ~/ubuntu-cis-audit/audit-specs/baselines/production-baseline.yaml
git add audit-specs/baselines/production-baseline.yaml
git commit -m "Add production baseline"
git push
```

3. **Audit other machines:**
```bash
# On any server
sudo nix run github:supabase/ubuntu-cis-audit#cis-audit -- --spec baselines/production-baseline.yaml
```

### Infrastructure-as-Code Validation

1. **Convert Ansible to GOSS:**
```bash
nix run github:supabase/ubuntu-cis-audit#ansible-to-goss ./ansible postgres-spec.yaml
```

2. **Validate deployed servers:**
```bash
sudo cis-audit --spec postgres-spec.yaml
```

## Repository Structure

```
ubuntu-cis-audit/
├── audit-specs/
│   ├── baselines/              # Custom baselines
│   │   ├── baseline.yml
│   │   └── README.md
│   ├── cis_level1_server.yaml  # Pre-defined CIS benchmarks
│   └── cis_level2_server.yaml
├── flake.nix                   # Nix flake definition
├── treefmt.nix                 # Code formatting config
├── .yamllint                   # YAML linting rules
└── LICENSE                     # Apache 2.0
```

## Development

### Code Quality

Pre-commit hooks are configured for:
- Shell script linting (shellcheck)
- Nix formatting (nixpkgs-fmt)
- YAML linting (yamllint)

```bash
# Format all files
nix fmt

# Run all checks
nix flake check
```

### Adding New Baselines

1. Generate baseline on target machine
2. Copy to `audit-specs/baselines/`
3. Use descriptive name (e.g., `postgres-production-baseline.yml`)
4. Document in `audit-specs/baselines/README.md`
5. Commit and push

## Requirements

- Nix (with flakes enabled)
- Target systems: Ubuntu 20.04+, aarch64 or x86_64
- `sudo` access for auditing and baseline generation

## License

Apache License 2.0 - see [LICENSE](LICENSE)

## Credits

- Built with [GOSS](https://github.com/goss-org/goss) by Ahmed Elsabbahy
- Developed for [Supabase](https://supabase.com)
- CIS benchmarks from [Center for Internet Security](https://www.cisecurity.org/)

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `nix flake check`
5. Submit a pull request

## Support

- Issues: [GitHub Issues](https://github.com/supabase/ubuntu-cis-audit/issues)
- Discussions: [GitHub Discussions](https://github.com/supabase/ubuntu-cis-audit/discussions)
