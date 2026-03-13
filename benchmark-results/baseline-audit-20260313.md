# Baseline Audit - win-target - 2026-03-13

## System

| Property | Value |
|----------|-------|
| Hostname | WIN-TARGET |
| OS | Windows Server 2022 Standard |
| Memory | 16 GB total, ~8 GB free |
| Uptime | ~1 day 10h |
| WinRM | HTTPS on port 5986, cert-based |

## WinRM Quotas (Pre-Existing State)

Someone (a prior project's `common` role or manual intervention) previously set all shell quotas
to max int32. This is the state BEFORE any changes by this project.

| Quota | Current Value | Windows Default | Notes |
|-------|--------------|-----------------|-------|
| MaxShellsPerUser | **2,147,483,647** | 30 | MAX INT — completely open |
| MaxProcessesPerShell | **2,147,483,647** | 25 | MAX INT — completely open |
| MaxMemoryPerShellMB | **2,147,483,647** | 1024 | MAX INT — completely open |
| MaxConnections | **300** | 25 | Elevated from default |
| MaxConcurrentOperationsPerUser | 1,500 | 1,500 | At default |
| MaxConcurrentUsers | null (unlimited?) | 10 | Not set or unlimited |
| IdleTimeout | 7,200,000ms (2h) | 7,200,000ms | At default |

## Active Sessions

| Metric | Value |
|--------|-------|
| Active shells | 3 |
| wsmprovhost processes | 0 |

## Safe Benchmark (forks=5, 3 iterations)

| Metric | Value |
|--------|-------|
| Duration | 1m 16s |
| Pre-benchmark shells | 4 |
| Post-benchmark shells | 4 |
| wsmprovhost processes | 0 |

## Implications for Demo

With quotas at max int32, the forkbomb cannot be reproduced. The demo sequence is:

1. `just reset-quotas` — restore Windows defaults (MaxShellsPerUser=30)
2. `just benchmark-safe` — verify forks=5 still works
3. `just benchmark-unsafe` — forks=50, should hit quota limit at 30 shells
4. `just deploy-quotas` — apply our elevated quotas (MaxShellsPerUser=100)
5. `just benchmark-unsafe` — forks=50, should now succeed
6. Optionally: `just benchmark-psrp` — show pypsrp doesn't have this issue

## Quota Toggle Reference

```bash
# Reset to Windows defaults (vulnerable to forkbomb)
just reset-quotas

# Apply safe elevated quotas
just deploy-quotas

# Apply with custom values
cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags winrm-quota \
  -e winrm_quota_max_shells_per_user=200
```
