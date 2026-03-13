# WSMan Plugin-Level Quotas and Credential Resolution

## The Hidden Second Layer

Windows WinRM has **two distinct quota levels** that are commonly confused:

### Level 1: Shell Quotas (`winrm/config/winrs` / `WSMan:\localhost\Shell\`)

These control WinRM connection resources:
- MaxShellsPerUser, MaxConcurrentUsers, MaxProcessesPerShell, etc.
- Set via `Set-Item WSMan:\localhost\Shell\<name>`
- Documented in most Ansible/WinRM troubleshooting guides

### Level 2: Plugin Quotas (`WSMan:\localhost\Plugin\microsoft.powershell\Quotas\`)

These control the PowerShell remoting endpoint specifically:
- MaxShells, MaxShellsPerUser, MaxConcurrentUsers, MaxProcessesPerShell
- MaxConcurrentCommandsPerShell, MaxConcurrentOperationsPerUser
- **Often have LOWER defaults than Shell quotas**

| Setting | Shell Default | Plugin Default | Effective |
|---------|--------------|----------------|-----------|
| MaxShellsPerUser | 30 | 25 | **25** (min) |
| MaxConcurrentUsers | 10 | 5 | **5** (min) |
| MaxProcessesPerShell | 25 | 15 | **15** (min) |

The effective limit is the **minimum** of both layers. Most documentation only
covers Shell-level quotas, so the plugin layer is the hidden bottleneck.

## Connection to KeePassXC Credential Plugin Issues

### Observed Behavior

During parallel molecule tests, KeePassXC credential resolution sometimes:
- Times out or returns errors
- Causes "credentials rejected" failures
- Appears to serialize or queue under load

### Hypothesis

Each Ansible credential lookup (KeePassXC, SOPS, env var) executes during
inventory initialization. During parallel molecule execution:

1. 4 molecule processes start simultaneously
2. Each initializes inventory → triggers credential lookup
3. Each credential lookup may create WinRM-adjacent operations
4. Plugin-level `MaxConcurrentOperationsPerUser` quota limits concurrent operations
5. If credential resolution is expensive or slow:
   - Subsequent lookups queue or fail
   - Timeouts cascade into "credentials rejected" errors
   - Retries amplify the load

### Key Difference: Shell vs Plugin Impact

- **Shell quota exhaustion** → new shells can't be created → task-level failures
- **Plugin quota exhaustion** → concurrent PowerShell operations throttled →
  credential resolution latency increases → cascading timeouts

### Prior Configuration

A prior project's `common` role correctly configures BOTH levels:
```yaml
# Shell level
common_winrm_max_shells_per_user: 100
# Plugin level (via WSMan:\localhost\Plugin\microsoft.powershell\Quotas)
common_winrm_max_concurrent_operations: 2500
```

This mirrors `MaxShellsPerUser` at both levels and raises plugin-level
`MaxConcurrentOperationsPerUser` from 1500 → 2500.

### Gap in Current Analysis

The PLAN.md fork bomb analysis is **Shell-centric** — it doesn't analyze:
- Whether credential plugin operations count against plugin quotas
- If plugin `MaxConcurrentOperationsPerUser` is the actual bottleneck
- How KeePassXC's per-process 5-minute TTL caching interacts with
  parallel molecule processes (no inter-process cache sharing)

## Recommendations

1. **Always configure both quota levels** — the `winrm_quota_config` role
   should set plugin quotas alongside shell quotas
2. **Instrument credential resolution latency** during parallel tests
3. **Consider inter-process credential caching** (e.g., Redis, memcached,
   or filesystem-based cache) for parallel molecule scenarios
4. **Monitor plugin quota usage** alongside shell quotas in the Grafana dashboard

## AD Account Permissions

### svc-ansible vs Standard AD Accounts

The ability to modify WSMan quotas requires specific AD group membership:

| Operation | Required Permission | svc-ansible | Standard AD user |
|-----------|-------------------|-------------|------------------|
| Read WSMan quotas | WinRM user access | Yes | ? |
| Set Shell quotas | Local Administrator | Yes (admin) | May vary |
| Set Plugin quotas | Local Administrator | Yes (admin) | May vary |
| Restart WinRM service | Local Administrator | Yes | May vary |
| Modify GPO-controlled quotas | Domain Admin / GPO editor | Depends | No |

**Service accounts** (svc-ansible, etc.) are domain admin or local admin on
managed Windows hosts. Regular AD accounts may not have the same privilege
level, which affects whether quota changes can be applied in automation.

### win-target Local Administrators Group (Observed 2026-03-13)

```
BUILTIN\Administrators:
  - Administrator          (local account)
  - YOURDOM\Domain Admins     (domain admin group)
  - YOURDOM\other-admin       (individual admin account)
  - YOURDOM\Infra-Admins      (infrastructure team group)
  - YOURDOM\Vuln-Scanner      (vulnerability scanner)
  - YOURDOM\win-target-island  (per-host island group)
```

### How svc-ansible Gets Admin Rights

`svc-ansible` is a member of `YOURDOM\win-target-island` (the per-host AD group), which
is in the local Administrators group. This is the "island" pattern — each
host has its own AD group, and service accounts are added per-host.

**Notable**: `svc-ansible` is NOT a Domain Admin. Admin rights come from island
group membership, not domain-level privilege.

### Service Account vs Standard AD Account

| Capability | svc-ansible | Standard AD user |
|------------|-------------|------------------|
| Local admin on win-target | Yes (via island group) | No (standard user) |
| Modify WSMan quotas | Yes | No |
| Restart WinRM service | Yes | No |
| Read WSMan quotas | Yes | Possibly (WinRM user) |
| RDP access | Yes | Yes (via YOURDOM\Staff?) |
| Domain Admin | No | No |

### Implications for Automation

1. **Quota changes require service account** — standard AD users cannot modify quotas
2. **Island group pattern** means admin access is per-host, not blanket
3. **Infra-Admins** also has admin rights — the infrastructure team can set quotas
   via GPO or direct configuration independently
4. A **dedicated automation service account** in the island group would be
   the production pattern for unattended quota management

### Research Questions

1. Can standard AD users connect to WinRM at all? (WinRM may require admin or
   explicit WinRM user group membership)
2. Does the per-host island group exist for ALL managed Windows hosts?
3. Could a GPO set safe defaults for all managed Windows hosts simultaneously?
4. Should the quota config role be run by the infrastructure team rather than developers?
