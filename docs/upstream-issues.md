# Upstream Issues & Contribution Targets

## Active Issues

### pywinrm#277 - Multi-Threaded WinRM Requests Fail
- **Repo**: [diyan/pywinrm](https://github.com/diyan/pywinrm/issues/277)
- **Problem**: Shared Session instances fail with concurrent threads because NTLM/Kerberos auth is stateful per-connection
- **Root Cause**: requests + urllib3 connection pool not designed for stateful auth protocols
- **Impact**: Each thread/fork needs its own Protocol instance
- **Potential Contribution**: Connection pooling improvements, thread-safe session management

### molecule#607 - WinRM Connection Plugin Issues
- **Repo**: [ansible/molecule](https://github.com/ansible/molecule/issues/607)
- **Problem**: Molecule's connection_options can only be configured once per scenario, making multi-host Windows testing difficult
- **Impact**: WinRM connections must use host_vars instead of group_vars for proper configuration
- **Potential Contribution**: Per-host connection_options support, WinRM-aware parallel testing

### ansible.windows#597 - Intermittent WinRM Failures at Scale
- **Repo**: [ansible-collections/ansible.windows](https://github.com/ansible-collections/ansible.windows/issues/597)
- **Problem**: Connection resets, refused connections, name resolution failures after initial successful tasks
- **Resolution**: Community recommends switching to pypsrp
- **Impact**: pypsrp is the recommended path forward for reliable Windows automation

## Potential Contributions

### 1. Molecule WinRM Safety Defaults
- Default `serial: 1` when connection=winrm is detected
- Warning when `forks > MaxShellsPerUser` for WinRM targets
- Quota pre-check as a molecule test stage

### 2. pywinrm Connection Pool Fix
- Thread-safe Protocol wrapper
- Connection reuse across tasks within a fork
- Shell creation rate limiting

### 3. Ansible WinRM Quota Awareness
- Callback plugin that monitors shell count during execution
- Automatic fork reduction when approaching quota limits
- Pre-flight quota check before play execution

### 4. WinRM Session Cleanup Module
- Ansible module (not role) for enumerating/terminating shells
- Could be contributed to community.windows collection
- Useful as a pre/post task in automation pipelines

## Related Resources

- [Microsoft WinRM Quotas](https://learn.microsoft.com/en-us/windows/win32/winrm/quotas)
- [WinRM Installation and Configuration](https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management)
- [Ansible Windows Guide](https://docs.ansible.com/projects/ansible/latest/os_guide/windows_winrm.html)
- [pypsrp Repository](https://github.com/jborean93/pypsrp)
