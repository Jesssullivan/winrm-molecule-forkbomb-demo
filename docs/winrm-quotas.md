# WinRM Quota Reference

## Querying Current Quotas

### PowerShell

```powershell
# Shell quotas
Get-Item WSMan:\localhost\Shell\MaxShellsPerUser
Get-Item WSMan:\localhost\Shell\MaxProcessesPerShell
Get-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB
Get-Item WSMan:\localhost\Shell\IdleTimeout

# Service quotas
Get-Item WSMan:\localhost\Service\MaxConcurrentUsers
Get-Item WSMan:\localhost\Service\MaxConcurrentOperationsPerUser
Get-Item WSMan:\localhost\Service\MaxConnections

# Full config dump
winrm get winrm/config
```

### From Ansible

```bash
just audit  # Runs audit-winrm.yml
```

## Setting Quotas

### PowerShell (Direct)

```powershell
Set-Item WSMan:\localhost\Shell\MaxShellsPerUser -Value 100
Set-Item WSMan:\localhost\Shell\MaxProcessesPerShell -Value 50
Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 2048
Set-Item WSMan:\localhost\Shell\IdleTimeout -Value 300000
Set-Item WSMan:\localhost\Service\MaxConcurrentUsers -Value 25
Set-Item WSMan:\localhost\Service\MaxConcurrentOperationsPerUser -Value 4294967295
```

### Via winrm CLI

```cmd
winrm set winrm/config/winrs @{MaxShellsPerUser="100"}
winrm set winrm/config/winrs @{MaxProcessesPerShell="50"}
winrm set winrm/config/winrs @{IdleTimeout="300000"}
winrm set winrm/config/service @{MaxConcurrentUsers="25"}
winrm set winrm/config/service @{MaxConcurrentOperationsPerUser="4294967295"}
```

### Via Ansible (This Project)

```bash
just deploy-quotas
```

### Via Group Policy

Computer Configuration → Administrative Templates → Windows Components:
- Windows Remote Management (WinRM) → WinRM Service
- Windows Remote Shell

## Quota Presets (from Dhall)

### Windows Default (Causes Forkbomb)

| Setting | Value |
|---------|-------|
| MaxShellsPerUser | 30 |
| MaxConcurrentUsers | 10 |
| MaxProcessesPerShell | 25 |
| IdleTimeout | 7200000ms (2 hours) |
| MaxMemoryPerShellMB | 1024 |

### Safe (For Normal Automation)

| Setting | Value |
|---------|-------|
| MaxShellsPerUser | 100 |
| MaxConcurrentUsers | 25 |
| MaxProcessesPerShell | 50 |
| IdleTimeout | 300000ms (5 min) |
| MaxMemoryPerShellMB | 2048 |

### Stress (For Benchmarking)

| Setting | Value |
|---------|-------|
| MaxShellsPerUser | 2147483647 (max int32) |
| MaxConcurrentUsers | 100 |
| MaxProcessesPerShell | 2000000000 |
| IdleTimeout | 600000ms (10 min) |
| MaxMemoryPerShellMB | 4096 |

## Observed State: vmnode852 (2026-03-13)

The EMS `common` role previously set all shell quotas to max int32. This is the
pre-existing state before any changes by this project:

| Setting | Observed | Windows Default |
|---------|----------|-----------------|
| MaxShellsPerUser | 2,147,483,647 | 30 |
| MaxProcessesPerShell | 2,147,483,647 | 25 |
| MaxMemoryPerShellMB | 2,147,483,647 | 1024 |
| MaxConnections | 300 | 25 |
| MaxConcurrentOperationsPerUser | 1,500 | 1,500 |
| IdleTimeout | 7,200,000ms | 7,200,000ms |

## Toggleable Quota Tool

The `winrm_quota_config` role + `just` recipes provide a toggleable admin tool:

```bash
# View current state (read-only, safe anytime)
just audit

# Reset to Windows defaults (for reproducing the forkbomb)
just reset-quotas

# Apply safe elevated quotas (the fix)
just deploy-quotas

# Apply custom values via extra vars
cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags winrm-quota \
  -e winrm_quota_max_shells_per_user=200 \
  -e winrm_quota_max_concurrent_users=50

# Apply a named Dhall preset
just dhall-render  # generates dhall/output/quota-presets.yaml
# Then reference values from the YAML
```

### Preset Profiles (from Dhall)

The three quota presets are defined type-safely in `dhall/quotas.dhall`:

- **`windowsDefault`**: Factory settings. Vulnerable to forkbomb at forks > ~6.
- **`safe`**: Elevated for normal automation (MaxShells=100). Handles forks=20 comfortably.
- **`stress`**: Maximum values for benchmarking. Use with monitoring active.

### Packaging for N&I

The quota config role could be extracted as a standalone Ansible collection or
Galaxy role for N&I to deploy across all managed Windows hosts:

```yaml
# Example: include in any playbook
- hosts: windows_servers
  roles:
    - role: winrm_quota_config
      winrm_quota_max_shells_per_user: 100
      winrm_quota_max_concurrent_users: 25
      tags: [winrm-quota]
```

## References

- [Microsoft WinRM Quotas](https://learn.microsoft.com/en-us/windows/win32/winrm/quotas)
- [WinRM Installation and Configuration](https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management)
