# winrm-molecule-forkbomb-demo

Research project demonstrating how Ansible's WinRM connection model causes a "forkbomb"
of authentication failures that exhaust Windows shell quotas and trigger Active Directory
account lockouts.

## The Problem

```
Ansible forks=50 × 15 tasks/role = 750 WinRM shell attempts
Windows MaxShellsPerUser = 30 → 720 failures
Each failure = failed NTLM auth → AD lockout after 5 failures
```

## The Fix

1. **Admin toggle**: Raise WinRM quotas before parallel testing (`winrm_quota_config` role)
2. **Session cleanup**: Auto-terminate stale WinRM shells (`winrm_session_cleanup` role)
3. **Use pypsrp**: Better connection pooling via PowerShell Remoting Protocol

## Quick Start

```bash
direnv allow                 # Enter nix dev shell
just setup                   # Install deps + collections
sops secrets/winrm-creds.enc.yaml  # Configure credentials
just tunnel-start            # SSH tunnel to vmnode852
just audit                   # Verify connectivity + baseline quotas

# Demo the forkbomb
just benchmark-safe          # forks=5, works fine
just benchmark-unsafe        # forks=50, demonstrates the problem
just deploy-quotas           # Apply the fix (raise quotas)
just benchmark-unsafe        # forks=50, now works!
just benchmark-psrp          # Compare pypsrp connection behavior
```

## Stack

- **Nix flake** + **direnv** - Reproducible dev shell
- **UV** + **pyproject.toml** - Python 3.13 dependency management
- **Dhall** - Type-safe configuration generation (quotas, benchmarks, role manifests)
- **SOPS** + **age** - Encrypted credential management
- **Ansible** + **Molecule** - Infrastructure automation and testing
- **just** - Task orchestration

## Roles

| Role | Purpose | Tags |
|------|---------|------|
| `winrm_quota_config` | Raise WinRM shell quotas (admin toggle) | `winrm-quota` |
| `winrm_session_cleanup` | Detect + terminate stale sessions | `winrm-cleanup` |
| `firewall_rules` | Windows firewall for IIS/WinRM | `firewall` |
| `iis_site` | Demo IIS site displaying repo contents | `iis-site` |

## Documentation

- [Forkbomb Mechanism](docs/forkbomb-mechanism.md) - Root cause analysis
- [WinRM Quotas](docs/winrm-quotas.md) - Quota reference and presets
- [pywinrm vs pypsrp](docs/pywinrm-vs-pypsrp.md) - Connection plugin comparison
- [AD Lockout Prevention](docs/ad-lockout-prevention.md) - Safety procedures
- [Upstream Issues](docs/upstream-issues.md) - Contribution targets

## Upstream Issues

- [pywinrm#277](https://github.com/diyan/pywinrm/issues/277) - Multi-threaded requests fail
- [molecule#607](https://github.com/ansible/molecule/issues/607) - WinRM connection plugin gaps
- [ansible.windows#597](https://github.com/ansible-collections/ansible.windows/issues/597) - Intermittent failures at scale
