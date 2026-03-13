# WinRM Quota Research Report

Research conducted 2026-03-13 for the WinRM molecule forkbomb demo project.
Sources: Microsoft Learn documentation, DISA STIGs, CIS Benchmarks, Ansible
project issues, community field reports.

---

## 1. Default Quota Values by Windows Version

### Shell-Level Defaults (winrm/config/winrs)

These values have remained **unchanged** from Windows Server 2008 R2 (WinRM 2.0)
through Windows Server 2025:

| Setting | Default | Notes |
|---------|---------|-------|
| MaxShellsPerUser | 30 | Per-user, per-machine |
| MaxConcurrentUsers | 10 | Distinct users with open shells |
| MaxProcessesPerShell | 25 | Including the shell process itself |
| MaxMemoryPerShellMB | 1024 | Microsoft warns against lowering below default |
| IdleTimeout | 7,200,000 ms (2 hrs) | Min value: 1,000 ms |
| MaxShellRunTime | 2,147,483,647 | **Read-only since WinRM 2.0** |
| AllowRemoteShellAccess | true | |

Example `winrm get winrm/config` output confirming these:

```
Winrs
    AllowRemoteShellAccess = true
    IdleTimeout = 7200000
    MaxConcurrentUsers = 10
    MaxProcessesPerShell = 25
    MaxMemoryPerShellMB = 1024
    MaxShellsPerUser = 30
```

Source: https://learn.microsoft.com/en-us/windows/win32/winrm/quotas

### Service-Level Defaults (winrm/config/service)

| Setting | Default | Notes |
|---------|---------|-------|
| MaxConnections | 300 | Was 25 in WinRM 2.0 |
| MaxConcurrentOperationsPerUser | 1,500 | Replaced MaxConcurrentOperations |
| MaxConcurrentOperations | 4,294,967,295 | **Deprecated/read-only since WinRM 2.0** |
| MaxPacketRetrievalTimeSeconds | 120 | |
| EnumerationTimeoutms | 240,000 | |
| MaxEnvelopeSizekb | 500 | Max supported: 1,039,440 |

Source: https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management

### Plugin-Level Defaults (WSMan:\localhost\Plugin\microsoft.powershell\Quotas)

The PowerShell plugin has its **own** quota layer, often overlooked:

| Setting | Default | Notes |
|---------|---------|-------|
| MaxShells | 25 | Total shells for the plugin |
| MaxShellsPerUser | 25 | Per-user within this plugin |
| MaxConcurrentUsers | 5 | **Lower than shell-level default** |
| MaxProcessesPerShell | 15 | **Lower than shell-level default** |
| MaxMemoryPerShellMB | 1024 | |
| MaxIdleTimeoutms | 2,147,483,647 | |
| IdleTimeoutms | 7,200,000 | |

The plugin-level quotas are the ones that **actually bite** in practice because
the effective limit is the **minimum** of the shell-level and plugin-level values.

### Version-Specific Changes

| Version | Change |
|---------|--------|
| WinRM 1.1 (Server 2008) | Original quota system |
| WinRM 2.0 (Server 2008 R2) | Major overhaul: MaxShellRunTime and MaxConcurrentOperations become read-only. MaxConcurrentOperationsPerUser introduced. MaxConnections default was 25. |
| Server 2012/2012 R2 | MaxConnections default increased to 300. No other changes. |
| Server 2016 | No quota changes |
| Server 2019 | No quota changes |
| Server 2022 | No quota changes |
| Server 2025 | No documented quota changes |

### Client vs Server Editions

Windows 10/11 client editions use the same shell-level defaults as Server.
The primary difference is operational: client systems typically have fewer
concurrent remote management sessions. The quota values themselves are identical.

---

## 2. Quota Behavior

### Do Changes Require Service Restart?

**Partially.** The behavior is nuanced:

- Changes via `Set-Item WSMan:\localhost\Shell\*` are written to the registry
  immediately
- **Existing connections** continue using old quota limits until terminated
- **New connections** reportedly pick up changes for some settings without restart
- Microsoft documentation states: "Most WinRM configuration changes take effect
  immediately for new connections"
- However, **in practice**, quota settings (especially MaxShellsPerUser) are
  reported to require `Restart-Service WinRM` to take full effect
- The safest approach is to **always restart** after quota changes

### Error When MaxShellsPerUser Exceeded

**WSMAN Error Code:** `2150858843` (not 2150859174 -- that's concurrent operations)

**PowerShell error:**
```
New-PSSession : [computername] Connecting to remote server failed with the
following error message: The WS-Management service cannot process the request.
The maximum number of concurrent shells for this user has been exceeded.
Close existing shells or raise the quota for this user.
For more information, see the about_Remote_Troubleshooting Help topic.
```

**Alternate wording (when plugin quota hit):**
```
The maximum number of concurrent shells allowed for this plugin has been exceeded.
```

**SOAP Fault:**
```xml
<s:Fault>
  <s:Code>
    <s:Value>s:Receiver</s:Value>
  </s:Code>
  <s:Reason>
    <s:Text>The WS-Management service cannot process the request.
    This user is allowed a maximum number of [N] concurrent shells,
    which has been exceeded. Close existing shells or raise the quota
    for this user.</s:Text>
  </s:Reason>
</s:Fault>
```

The Ansible winrm.py connection plugin specifically handles WSManFault error code
`0x803381A6` for quota exhaustion scenarios.

### Error When MaxConcurrentOperationsPerUser Exceeded

**WSMAN Error Code:** `2150859174`

```
The WS-Management service cannot process the request. This user is allowed a
maximum number of 15 concurrent operations, which has been exceeded. Close
existing operations for this user, or raise the quota for this user.
```

### Error When MaxConcurrentUsers Exceeded

```
The WS-Management service cannot process the request. The server exceeded the
maximum number of users concurrently performing remote operations on the same
system. Retry later.
```

---

## 3. WinRM Service Restart Behavior

### What Happens with `Restart-Service WinRM` Remotely

1. The command begins executing on the remote host
2. The WinRM service stops, **immediately dropping the remote session**
3. The PowerShell/Ansible session hangs briefly, then errors:
   ```
   The WinRM service was stopped while this remote session was in use.
   Please reconnect to the remote computer to continue your work.
   ```
4. The WinRM service restarts automatically (it's a restart, not just stop)
5. There is a **brief window** where the host is unreachable

### HTTPS Listener Rebinding

- The HTTPS listener **does** rebind automatically after restart in most cases
- `http.sys` caches certificate bindings, so even if WinRM reports a stale
  thumbprint, the correct certificate is typically presented
- Known edge case: if the certificate referenced by the listener has expired
  AND no valid replacement exists, HTTPS will fail post-restart
- WinRM does **not** automatically update its listener's CertificateThumbprint
  when a certificate is renewed, but `http.sys` selects the newest valid
  Server Authentication certificate anyway (documented in PowerShell/PowerShell#2282)

### Known Issues After Remote Restart

1. **Certificate thumbprint mismatch**: WinRM may report old thumbprint but
   actually use new cert (http.sys behavior)
2. **Dependent service ordering**: WinHttpAutoProxySvc may not restart correctly
3. **Brief authentication failures**: Kerberos ticket validation may be
   temporarily unavailable
4. **Firewall state**: Windows Firewall rules survive restart, but there's a
   brief window during service startup

### Safe Remote Restart Strategies

**Recommended: Scheduled task approach**
```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-Command 'Start-Sleep -Seconds 10; Restart-Service WinRM -Force'"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
Register-ScheduledTask -TaskName "RestartWinRM" -Action $action `
  -Trigger $trigger -RunLevel Highest -User "SYSTEM"
# Exit session before the scheduled time
```

**Alternative: Use `win_service` module with async**
```yaml
- name: Schedule WinRM restart
  ansible.windows.win_scheduled_task:
    name: RestartWinRM
    actions:
      - path: powershell.exe
        arguments: "-Command 'Start-Sleep 10; Restart-Service WinRM -Force'"
    triggers:
      - type: time
        start_boundary: "{{ '%Y-%m-%dT%H:%M:%S' | strftime((ansible_date_time.epoch | int) + 30) }}"
    username: SYSTEM
    run_level: highest
    state: present
    enabled: true
```

### Does `Set-Item WSMan:\` Require Restart?

Microsoft documentation is contradictory on this point:
- Official docs say "Most WinRM configuration changes take effect immediately
  for new connections"
- Practical experience shows quota changes (especially MaxShellsPerUser) do
  not reliably take effect without a restart
- **Recommendation**: Always restart after quota changes in production

---

## 4. Group Policy and WinRM Quotas

### GPO Paths

**Service-level settings:**
```
Computer Configuration
  -> Administrative Templates
    -> Windows Components
      -> Windows Remote Management (WinRM)
        -> WinRM Service
```

Available settings include:
- Allow Basic authentication
- Allow unencrypted traffic
- Disallow WinRM from storing RunAs credentials
- Turn on Compatibility HTTP Listener / HTTPS Listener

**Shell-level settings:**
```
Computer Configuration
  -> Administrative Templates
    -> Windows Components
      -> Windows Remote Shell
```

Available settings include:
- Allow Remote Shell Access
- MaxConcurrentUsers
- MaxShellsPerUser
- MaxProcessesPerShell
- MaxMemoryPerShellMB
- Specify idle Timeout
- Specify maximum number of remote shells per user (redundant with above)

### GPO Override Behavior

**Group Policy settings ALWAYS override WSMan provider values.**

- When a GPO is applied, the corresponding local settings become read-only
- GPO reapplication occurs every 90-120 minutes on domain members
- `gpupdate /force` forces immediate reapplication
- Local changes via `Set-Item WSMan:\` may appear to succeed but will be
  overwritten on next GPO refresh cycle
- This is a common source of confusion: admin sets value, verifies with
  `Get-Item`, sees the change, but the old GPO value takes effect after refresh

### Registry Keys

**Shell quotas:**
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Shell
  MaxShellsPerUser (DWORD)
  MaxConcurrentUsers (DWORD)
  MaxProcessesPerShell (DWORD)
  MaxMemoryPerShellMB (DWORD)
  IdleTimeout (DWORD)
```

**Service quotas:**
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Service
  MaxConnections (DWORD)
  MaxConcurrentOperationsPerUser (DWORD)
```

**Plugin quotas (PowerShell):**
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Plugin\Microsoft.PowerShell\Quotas
  MaxShells (DWORD)
  MaxShellsPerUser (DWORD)
  MaxConcurrentUsers (DWORD)
  MaxProcessesPerShell (DWORD)
  MaxMemoryPerShellMB (DWORD)
```

### Persistence Behavior

| Method | Persists across restart? | Persists across reboot? | Subject to GPO override? |
|--------|------------------------|------------------------|-------------------------|
| `Set-Item WSMan:\` | Yes | Yes | Yes |
| `winrm set` CLI | Yes | Yes | Yes |
| Direct registry edit | Yes | Yes | Yes |
| Group Policy | Yes (re-enforced) | Yes (re-enforced) | N/A (is GPO) |

Values set by any method persist in the registry. The key distinction is that
GPO-set values are **re-enforced** on every policy refresh cycle, overriding
any local changes.

---

## 5. Connection Limits vs Shell Limits

### Architecture Layers

```
MaxConnections (Service)          <- Total HTTP/HTTPS connections to WinRM service
  |
  +-- MaxConcurrentUsers          <- Distinct user accounts with active sessions
  |     (Service and Shell)
  |
  +-- MaxShellsPerUser            <- Remote shell sessions per user
  |     (Shell and Plugin)
  |
  +-- MaxProcessesPerShell        <- Processes within each shell
        (Shell and Plugin)
```

### Effective Limit Calculation

The effective limit for any user is the **minimum** across all layers:

- **MaxShellsPerUser**: min(Shell-level=30, Plugin-level=25) = **25**
- **MaxConcurrentUsers**: min(Shell-level=10, Plugin-level=5) = **5**
- **MaxProcessesPerShell**: min(Shell-level=25, Plugin-level=15) = **15**

This is why you often see errors citing "5 concurrent shells" even though
the shell-level default is 30 -- the plugin-level default of 25 shells
(or 5 concurrent users) is the binding constraint.

### MaxConnections vs MaxShellsPerUser

| Aspect | MaxConnections | MaxShellsPerUser |
|--------|---------------|-----------------|
| Scope | Entire WinRM service | Per-user, per-machine |
| Config path | winrm/config/service | winrm/config/winrs |
| Default | 300 | 30 (shell) / 25 (plugin) |
| What it limits | Total HTTP/HTTPS connections | Remote shell sessions |
| Error when exceeded | Connection refused at network level | WSMan fault returned |

### Theoretical Maximum Resource Consumption

With defaults: MaxMemoryPerShellMB(1024) x MaxShellsPerUser(30) x
MaxConcurrentUsers(10) = **307,200 MB** (~300 GB). In practice, system RAM
is the real constraint.

### NTLM vs Kerberos Connection Impact

- Both authentication types count as **one connection** toward MaxConnections
- Kerberos: Mutual authentication, single round-trip after ticket acquisition
- NTLM: Challenge-response, potentially more overhead per connection setup
- NTLM does **not** use more WinRM connections than Kerberos
- However, NTLM cannot delegate credentials (double-hop problem), which may
  cause tasks to fail in ways that prompt retry loops, indirectly consuming
  more connections

---

## 6. WinRM Hardening vs Automation

### DISA STIG Requirements (Windows Server 2022 V2R4)

The STIG addresses WinRM authentication and encryption but does **not**
prescribe specific quota values:

| STIG ID | Rule | GPO Path |
|---------|------|----------|
| V-254378 (WN22-CC-000480) | WinRM **client** must not use Basic auth | Computer Config -> Admin Templates -> Windows Components -> WinRM -> WinRM Client -> Allow Basic authentication: **Disabled** |
| V-254379 (WN22-CC-000490) | WinRM **client** must not allow unencrypted traffic | ... -> WinRM Client -> Allow unencrypted traffic: **Disabled** |
| V-254380 (WN22-CC-000495) | WinRM **client** must not use Digest auth | ... -> WinRM Client -> Disallow Digest authentication: **Enabled** |
| V-254381 (WN22-CC-000500) | WinRM **service** must not use Basic auth | ... -> WinRM Service -> Allow Basic authentication: **Disabled** |
| V-254382 (WN22-CC-000510) | WinRM **service** must not allow unencrypted traffic | ... -> WinRM Service -> Allow unencrypted traffic: **Disabled** |
| V-254383 (WN22-CC-000520) | WinRM **service** must not store RunAs credentials | ... -> WinRM Service -> Disallow WinRM from storing RunAs credentials: **Enabled** |

### CIS Benchmark Guidance

CIS Benchmarks for Windows Server 2022 (v3.0.0) similarly focus on:
- Disabling Basic authentication (both client and service)
- Disabling unencrypted traffic
- Enabling PowerShell Script Block Logging
- Enabling PowerShell Transcription (L2)

**Neither CIS nor STIG prescribe specific values for MaxShellsPerUser,
MaxConcurrentUsers, MaxConnections, or other quota settings.**

### Implications for Ansible/Automation

The STIG and CIS requirements mean:
1. **Basic auth is prohibited** -- use Kerberos or NTLM (Negotiate)
2. **Unencrypted traffic is prohibited** -- use HTTPS (port 5986) or ensure
   message-level encryption via Negotiate/Kerberos
3. **CredSSP** is not addressed but generally discouraged for delegation;
   prefer Kerberos constrained delegation

For Ansible specifically:
- Use `ansible_winrm_transport: kerberos` or `ntlm`
- Use `ansible_port: 5986` with `ansible_winrm_scheme: https`
- Or use HTTP with `ansible_winrm_message_encryption: auto` (pywinrm >= 0.3.0
  encrypts NTLM/Kerberos traffic even over HTTP)

### Recommended Automation Quota Values

Based on field experience documented in community sources:

| Scenario | MaxShellsPerUser | MaxConcurrentUsers | MaxConnections | MaxProcessesPerShell |
|----------|-----------------|-------------------|---------------|---------------------|
| Single Ansible controller | 100 | 25 | 300 (default) | 50 |
| Multiple controllers / heavy automation | 200+ | 50-100 | 500+ | 100 |
| Benchmarking / stress testing | 2,147,483,647 | 100 | 1000+ | 2,000,000,000 |
| Windows default (forkbomb-vulnerable) | 30 | 10 | 300 | 25 |

### Ansible Forks vs WinRM Quotas

The critical relationship for this project:

- Ansible `forks` setting controls parallelism across hosts
- Each fork creates its own WinRM connection and shell to the target
- With molecule, **all forks target the same host** (win-target)
- Therefore: `forks` > `MaxShellsPerUser` = **connection exhaustion**
- With plugin-level defaults: `forks` > 25 = quota exceeded
- With shell-level defaults: `forks` > 30 = quota exceeded
- The "forkbomb" occurs because molecule retries failed connections,
  potentially amplifying the problem with AD account lockouts

---

## 7. Key Findings for the Forkbomb Demo

1. **Plugin-level quotas are the hidden constraint.** Most documentation
   discusses shell-level defaults (MaxShellsPerUser=30) but the PowerShell
   plugin defaults are lower (MaxShellsPerUser=25, MaxConcurrentUsers=5).
   The effective limit is the minimum of both layers.

2. **Defaults have not changed since WinRM 2.0 (2009).** The quota framework
   achieved stability 17 years ago. There is no version-specific behavior
   to account for between Server 2016/2019/2022/2025.

3. **Quota changes may not take effect without restart.** Despite Microsoft
   documentation suggesting otherwise, practical experience shows that
   `Restart-Service WinRM` is needed for reliable quota enforcement.

4. **Remote WinRM restart is inherently dangerous.** The connection drops
   immediately. Use scheduled tasks for deferred restart.

5. **GPO overrides everything.** If quotas are set via Group Policy,
   local `Set-Item WSMan:\` changes will be silently overridden on the
   next policy refresh (every 90-120 minutes).

6. **CIS/STIG do not constrain quotas.** Security frameworks focus on
   authentication and encryption, not resource quotas. Organizations are
   free to set quota values appropriate for their automation needs.

7. **The WinRM error for quota exhaustion is distinctive** and includes
   the specific limit that was hit, making diagnosis straightforward.

---

## References

### Microsoft Documentation
- [WinRM Quota Management](https://learn.microsoft.com/en-us/windows/win32/winrm/quotas)
- [WinRM Installation and Configuration](https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management)
- [What's New in WinRM](https://learn.microsoft.com/en-us/windows/win32/winrm/whats-new-in-winrm)
- [Configure WinRM for HTTPS](https://learn.microsoft.com/en-us/troubleshoot/windows-client/system-management-components/configure-winrm-for-https)
- [MS-WSMV Protocol Extensions](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wsmv/77425799-79f6-4a9a-b164-3873e742d921)

### Security Frameworks
- [CIS Microsoft Windows Server 2022 Benchmark v3.0.0](https://www.cisecurity.org/benchmark/microsoft_windows_server)
- [DISA STIG Windows Server 2022 V2R4](https://stigviewer.com/stigs/microsoft-windows-server-2022-security-technical-implementation-guide)
- [NIST NCP Checklist 1188](https://ncp.nist.gov/checklist/1188)

### Ansible / WinRM Integration
- [Ansible WinRM Connection Plugin](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/winrm_connection.html)
- [Ansible Windows Remote Management Guide](https://ansible.readthedocs.io/projects/ansible-core/devel/os_guide/windows_winrm.html)
- [pywinrm GitHub](https://github.com/diyan/pywinrm)
- [ansible/ansible#25532 - Connection refused with WinRM](https://github.com/ansible/ansible/issues/25532)
- [ansible/ansible#30765 - WinRM service stopping during playbook](https://github.com/ansible/ansible/issues/30765)
- [ansible.windows#597 - Intermittent failures with large host count](https://github.com/ansible-collections/ansible.windows/issues/597)

### Community Resources
- [FoxDeploy: WinRM and HTTPS - What happens when certs die](https://www.foxdeploy.com/blog/winrm-and-https-what-happens-when-certs-die.html)
- [PowerShell/PowerShell#2282 - WinRM certificate implementation](https://github.com/PowerShell/PowerShell/issues/2282)
- [Gary Flynn: Increase WinRM/PowerShell Limits](https://garyflynn.com/post/increase-winrm-powershell-limits/)
- [Motadata: Configuring WinRM for Monitoring](https://www.motadata.com/nms-docs/knowledge-base/configuring-win-rm-to-monitor-windows-environment/)
