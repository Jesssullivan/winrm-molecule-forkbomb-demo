# pywinrm vs pypsrp Connection Plugin Comparison

## Architecture

| Aspect | pywinrm | pypsrp |
|--------|---------|--------|
| Protocol | WS-Management (SOAP over HTTP) | PSRP over WS-Management |
| Connection Model | New HTTP conn per task | Persistent Runspace Pool |
| Session Reuse | None | Full reuse within play |
| Auth per Task | Yes (new NTLM handshake) | No (session token reuse) |
| Shell Creation | New shell per task | Shared runspace pool |
| Connection Pool | Per-Protocol instance | Multiplexed over single conn |
| Thread Safety | Not thread-safe ([#277](https://github.com/diyan/pywinrm/issues/277)) | Thread-safe design |

## WinRM Quota Impact

### pywinrm at forks=20, 15 tasks per role

```
Total shell creations: 20 × 15 = 300
Peak concurrent shells: ~20 (one per fork)
Total NTLM auth attempts: 300
MaxShellsPerUser pressure: HIGH (300 shell create/destroy cycles)
```

### pypsrp at forks=20, 15 tasks per role

```
Total shell creations: 20 (one per fork, reused)
Peak concurrent shells: 20
Total NTLM auth attempts: 20 (once per connection)
MaxShellsPerUser pressure: LOW (20 persistent connections)
```

## Configuration

### pywinrm (default)

```yaml
# inventory/hosts.yml
vmnode852:
  ansible_connection: winrm
  ansible_winrm_transport: ntlm
  ansible_winrm_scheme: https
  ansible_winrm_server_cert_validation: ignore
```

### pypsrp

```yaml
# inventory/hosts.yml
vmnode852:
  ansible_connection: psrp
  ansible_psrp_auth: ntlm
  ansible_psrp_protocol: https
  ansible_psrp_cert_validation: false
  ansible_psrp_reconnection_retries: 3
```

## Performance

Based on [ansible.windows#597](https://github.com/ansible-collections/ansible.windows/issues/597):

- **pypsrp** is faster for looped tasks (connection reuse)
- **pypsrp** is more reliable at scale (fewer auth failures)
- **pypsrp** reduces AD lockout risk (fewer auth attempts)

## When to Use Each

| Scenario | Recommendation |
|----------|---------------|
| Small playbooks (<10 tasks) | Either works |
| Large playbooks (50+ tasks) | pypsrp |
| High forks (>10) | pypsrp |
| Parallel molecule tests | pypsrp |
| CI/CD pipelines | pypsrp |
| Shared AD service accounts | pypsrp (critical) |
| Debugging WinRM issues | pywinrm (more verbose logs) |

## Migration

Switch from pywinrm to pypsrp by changing the connection plugin:

```ini
# ansible.cfg
[defaults]
# No change needed - connection is per-host

# Or set globally:
# transport = psrp  # NOT recommended, breaks Linux hosts
```

```yaml
# Group vars for Windows hosts only
windows:
  vars:
    ansible_connection: psrp
```
