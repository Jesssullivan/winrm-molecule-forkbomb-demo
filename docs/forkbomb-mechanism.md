# WinRM Molecule Forkbomb Mechanism

## The Problem

When Ansible runs molecule tests against Windows hosts using WinRM, parallel execution
creates a cascade of connection failures that can lock out Active Directory accounts.

## Root Cause Chain

```
Ansible forks=N
  × tasks per role (~15-50)
  × concurrent molecule scenarios
  = Total WinRM shell creation attempts
```

### Layer 1: Ansible Forks

Ansible's `forks` setting (default: 5) controls how many hosts are managed simultaneously.
Each fork creates an **independent** WinRM connection with its own authentication.

### Layer 2: pywinrm Connection Model

The `pywinrm` library (Ansible's default WinRM transport) creates a **new WinRM shell
for every task**. There is no connection pooling or session reuse across tasks.

```
Task 1: New HTTP connection → NTLM auth → WinRM shell → execute → close shell
Task 2: New HTTP connection → NTLM auth → WinRM shell → execute → close shell
Task 3: New HTTP connection → NTLM auth → WinRM shell → execute → close shell
...
```

This is documented in [pywinrm#277](https://github.com/diyan/pywinrm/issues/277).

### Layer 3: WinRM Quota Limits

Windows enforces quotas on WinRM resources:

| Quota | Default | Description |
|-------|---------|-------------|
| MaxShellsPerUser | 30 | Max concurrent shells per user |
| MaxConcurrentUsers | 10 | Max concurrent user sessions |
| MaxProcessesPerShell | 25 | Max processes per shell |
| MaxMemoryPerShellMB | 1024 | Max memory per shell |
| IdleTimeout | 7200000ms | Shell auto-cleanup after 2 hours |

When `forks × concurrent_tasks > MaxShellsPerUser`, new shell creation fails.

### Layer 4: Authentication Failure Cascade

When WinRM rejects a shell creation request due to quota exhaustion:

1. Ansible receives "credentials rejected" error (misleading error message)
2. Ansible retries authentication (default retry behavior)
3. Each retry = a **failed NTLM auth attempt** against Active Directory
4. AD lockout threshold (typically 5 failed attempts in 15 minutes)
5. Account locks → ALL hosts using that account are locked out

### Layer 5: Molecule Amplification

When molecule tests run in parallel (e.g., `parallel -j4 molecule test`):

```
4 molecule processes × forks=5 × ~15 tasks = 300 shell creation attempts
MaxShellsPerUser = 30 → 270 failures → 270 failed auth attempts
AD lockout threshold = 5 → LOCKED after first 5 failures
```

## The Compounding Effect

```
                    ┌─────────────────┐
                    │  parallel -j4   │
                    │  molecule test  │
                    └────┬───┬───┬───┘
                         │   │   │
              ┌──────────┘   │   └──────────┐
              ▼              ▼              ▼
         ┌─────────┐   ┌─────────┐   ┌─────────┐
         │ forks=5  │   │ forks=5  │   │ forks=5  │
         │ Scenario1│   │ Scenario2│   │ Scenario3│
         └─────┬───┘   └─────┬───┘   └─────┬───┘
               │              │              │
               ▼              ▼              ▼
        ┌──────────────────────────────────────────┐
        │     win-target (MaxShellsPerUser=30)      │
        │                                          │
        │  Shell slots:  [##########]  (30 max)    │
        │  Concurrent:   15 × 3 = 45 attempted     │
        │  Overflow:     15 → "credentials rejected"│
        │  AD impact:    15 failed NTLM attempts   │
        │  Lockout:      YES (threshold=5)         │
        └──────────────────────────────────────────┘
```

## The Fix (Two-Part)

### Part 1: Raise WinRM Quotas (Admin Toggle)

The `winrm_quota_config` role elevates quotas before parallel testing:

```powershell
Set-Item WSMan:\localhost\Shell\MaxShellsPerUser -Value 100
Set-Item WSMan:\localhost\Service\MaxConcurrentUsers -Value 25
Set-Item WSMan:\localhost\Shell\MaxProcessesPerShell -Value 50
Set-Item WSMan:\localhost\Shell\IdleTimeout -Value 300000
```

### Part 2: Session Cleanup

The `winrm_session_cleanup` role installs a scheduled task that:
- Enumerates active WinRM shells every 15 minutes
- Terminates shells older than 30 minutes
- Prevents stale shell accumulation that erodes quota headroom

### Part 3: Use pypsrp Instead of pywinrm

The PSRP connection plugin (`ansible_connection=psrp`) uses PowerShell Remoting Protocol
which maintains persistent connections via a Runspace Pool. Multiple commands execute over
a single authenticated connection, dramatically reducing auth attempts.

See [ansible.windows#597](https://github.com/ansible-collections/ansible.windows/issues/597).

## Upstream Issues

- [pywinrm#277](https://github.com/diyan/pywinrm/issues/277) - Multi-threaded requests fail
- [molecule#607](https://github.com/ansible/molecule/issues/607) - WinRM connection plugin issues
- [ansible.windows#597](https://github.com/ansible-collections/ansible.windows/issues/597) - Intermittent WinRM failures
