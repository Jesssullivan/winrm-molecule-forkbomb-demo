# WinRM Defaults by Windows Server Version

## Research Note

This document captures WinRM/WSMan default quota values as shipped across
Windows Server versions. Findings are from Microsoft documentation, empirical
testing, and community research. Values may vary by edition (Standard vs Datacenter)
and cumulative update level.

## Quota Defaults by Version

### Shell/Winrs Quotas

| Setting | 2012 R2 | 2016 | 2019 | 2022 | 2025 |
|---------|---------|------|------|------|------|
| MaxShellsPerUser | 25 | 25 | 25 | 30 | 30 |
| MaxConcurrentUsers | 5 | 10 | 10 | 10 | 10 |
| MaxProcessesPerShell | 15 | 25 | 25 | 25 | 25 |
| MaxMemoryPerShellMB | 150 | 1024 | 1024 | 1024 | 1024 |
| IdleTimeout (ms) | 180000 | 7200000 | 7200000 | 7200000 | 7200000 |
| MaxShellRunTime (ms) | 28800000 | 2147483647 | 2147483647 | 2147483647 | 2147483647 |
| AllowRemoteShellAccess | true | true | true | true | true |

### Service Quotas

| Setting | 2012 R2 | 2016 | 2019 | 2022 | 2025 |
|---------|---------|------|------|------|------|
| MaxConnections | 25 | 25 | 25 | 25 | 25 |
| MaxConcurrentOperationsPerUser | 1500 | 1500 | 1500 | 1500 | 1500 |
| MaxPacketRetrievalTimeSeconds | 120 | 120 | 120 | 120 | 120 |

### Windows 10/11 Desktop Differences

Desktop Windows ships with WinRM disabled by default. When enabled:

| Setting | Windows 10 | Windows 11 |
|---------|------------|------------|
| MaxShellsPerUser | 30 | 30 |
| MaxConcurrentUsers | 5 | 5 |
| MaxProcessesPerShell | 25 | 25 |
| MaxMemoryPerShellMB | 1024 | 1024 |

Note: Desktop has lower `MaxConcurrentUsers` (5 vs 10 on Server).

## Key Version Changes

### 2012 R2 → 2016
- **MaxMemoryPerShellMB**: 150 → 1024 (7x increase)
- **MaxConcurrentUsers**: 5 → 10 (2x)
- **MaxProcessesPerShell**: 15 → 25
- **IdleTimeout**: 3 min → 2 hours
- **MaxShellRunTime**: 8 hours → max int32 (unlimited)

These changes reflected Microsoft's push toward Server Core and remote management
as the default administration model.

### 2019 → 2022
- **MaxShellsPerUser**: 25 → 30 (slight increase)
- All other values unchanged

### 2022 → 2025
- No changes observed in WinRM defaults
- Focus on HTTP/2 transport improvements and PSRP performance

## Do Quotas Require WinRM Restart?

**No.** WSMan quota changes via `Set-Item WSMan:\localhost\Shell\*` take effect
**immediately** on new shell creation. Existing shells are not affected.

This is a critical operational finding — our initial implementation included
`notify: restart winrm` which was destructive and unnecessary. See
`benchmark-results/finding-winrm-restart-20260313.md`.

### Registry Persistence

WSMan quotas are stored in the registry at:
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Plugin\Microsoft.PowerShell\Quotas
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Service
```

Changes via `Set-Item WSMan:\` write directly to the registry and persist across
WinRM service restarts and reboots.

## Error Messages

### MaxShellsPerUser Exceeded

```
ERROR CODE: 2150859174
The WS-Management service cannot process the request. The maximum number of
concurrent shells for this user has been exceeded. Close existing shells or
raise the quota for this user.
```

### MaxConcurrentOperationsPerUser Exceeded

```
ERROR CODE: 2150858842
The maximum number of concurrent operations for this user has been exceeded.
Close existing operations for this user, or raise the quota for this user.
```

### How Ansible Reports These

Ansible translates both as: `"credentials rejected"` or
`"The WinRM connection timed out"` — **misleading error messages** that don't
indicate the real cause (quota exhaustion). This is why the forkbomb causes
AD lockout: operators retry authentication thinking the password is wrong.

## Group Policy Control

WinRM quotas can be set via Group Policy:

```
Computer Configuration
  → Administrative Templates
    → Windows Components
      → Windows Remote Management (WinRM)
        → WinRM Service
          → Specify channel binding token hardening level
          → Allow remote server management through WinRM
          → Turn on Compatibility HTTP/HTTPS Listener
        → WinRM Client
```

And via Windows Remote Shell GPO:
```
Computer Configuration
  → Administrative Templates
    → Windows Components
      → Windows Remote Shell
        → Allow Remote Shell Access
        → MaxConcurrentUsers
        → Idle Timeout
        → MaxProcessesPerShell
        → MaxMemoryPerShellMB
        → MaxShellsPerUser
```

**GPO values override WSMan provider values.** If set via GPO, `Set-Item WSMan:\`
changes are rejected or overridden on next Group Policy refresh (every 90 min ± 30 min).

## CIS Benchmark / STIG Considerations

CIS Windows Server 2022 Benchmark recommends:
- WinRM service should be configured for HTTPS only (no HTTP listener)
- Basic auth should be disabled (`AllowBasic = false`)
- Unencrypted traffic should be disabled (`AllowUnencrypted = false`)
- WinRM digest auth should be disabled if not needed
- No specific guidance on MaxShellsPerUser values for automation

DISA STIG (V-254242, V-254243):
- WinRM must use HTTPS
- WinRM must not allow stored credentials
- No quota-specific requirements

## Recommendations for Automation Environments

| Scenario | MaxShellsPerUser | MaxConcurrentUsers | Notes |
|----------|-----------------|--------------------|----|
| Manual admin only | 30 (default) | 10 (default) | Fine |
| Single Ansible controller | 100 | 25 | Handles forks=20 |
| Multiple automation tools | 200+ | 50+ | Ansible + SCCM + GPO |
| CI/CD with parallel molecule | 500+ | 100+ | Or use pypsrp |
| Stress testing / research | max int32 | max int32 | Current win-target state |

## References

- [Microsoft WinRM Quotas](https://learn.microsoft.com/en-us/windows/win32/winrm/quotas)
- [WinRM Installation and Configuration](https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management)
- [Ansible Windows WinRM Guide](https://docs.ansible.com/projects/ansible/latest/os_guide/windows_winrm.html)
- [CIS Benchmark for Windows Server 2022](https://www.cisecurity.org/benchmark/microsoft_windows_server)
