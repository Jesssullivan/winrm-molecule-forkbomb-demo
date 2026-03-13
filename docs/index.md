# WinRM Forkbomb Demo

Research project demonstrating how Ansible's WinRM connection model causes a "forkbomb"
of authentication failures that exhaust Windows shell quotas and trigger Active Directory
account lockouts.

## The Problem

```
Ansible forks=50 x 15 tasks/role = 750 WinRM shell attempts
Windows MaxShellsPerUser = 30 -> 720 failures
Each failure = failed NTLM auth -> AD lockout after 5 failures
```

## Key Sections

- **[Forkbomb Mechanism](forkbomb-mechanism.md)** -- Root cause analysis of how Ansible's fork model interacts with WinRM quotas
- **[Parallelism Patterns](parallelism-patterns.md)** -- How different Ansible parallelism modes trigger the issue
- **[WinRM Quotas](winrm-quotas.md)** -- Quota reference, presets, and tuning guidance
- **[pywinrm vs pypsrp](pywinrm-vs-pypsrp.md)** -- Connection plugin comparison showing pypsrp eliminates auth failures
- **[Benchmark Results](benchmark-results.md)** -- Aggregate test data from reproduction and mitigation runs
- **[AD Lockout Prevention](ad-lockout-prevention.md)** -- Safety procedures for production environments
- **[Upstream Issues](upstream-issues.md)** -- Contribution targets in pywinrm, molecule, and ansible.windows

## Quick Start

```bash
direnv allow                 # Enter nix dev shell
just setup                   # Install deps + collections
sops secrets/winrm-creds.enc.yaml  # Configure credentials
just tunnel-start            # SSH tunnel to win-target
just audit                   # Verify connectivity + baseline quotas

# Demo the forkbomb
just benchmark-safe          # forks=5, works fine
just benchmark-unsafe        # forks=50, demonstrates the problem
just deploy-quotas           # Apply the fix (raise quotas)
just benchmark-unsafe        # forks=50, now works!
just benchmark-psrp          # Compare pypsrp connection behavior
```

## Stack

| Component | Purpose |
|-----------|---------|
| Nix flake + direnv | Reproducible dev shell |
| UV + pyproject.toml | Python 3.13 dependency management |
| Dhall | Type-safe configuration generation |
| SOPS + age | Encrypted credential management |
| Ansible + Molecule | Infrastructure automation and testing |
| just | Task orchestration |

## Roles

| Role | Purpose | Tags |
|------|---------|------|
| `winrm_quota_config` | Raise WinRM shell quotas (admin toggle) | `winrm-quota` |
| `winrm_session_cleanup` | Detect + terminate stale sessions | `winrm-cleanup` |
| `firewall_rules` | Windows firewall for IIS/WinRM | `firewall` |
| `iis_site` | Demo IIS site displaying repo contents | `iis-site` |
