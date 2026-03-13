# pywinrm vs pypsrp Connection Plugin Comparison

## Key Finding

**PSRP has been in `ansible.builtin` (ansible-core) since Ansible 2.7 (October 2018).**
It is NOT an external collection — it ships with every Ansible installation. Despite
being available for 7+ years, pywinrm remains the default and more widely documented
option, leaving many teams unaware of the superior alternative.

## History

| Date | Event |
|------|-------|
| Jul 2018 | pypsrp 0.1.0 published to PyPI by Jordan Borean (jborean93) |
| Aug 2018 | [PR #41729](https://github.com/ansible/ansible/pull/41729) merged into ansible-core |
| Oct 2018 | **Ansible 2.7.0** ships with `ansible.builtin.psrp` |
| 2020 | Ansible 2.10 collection split — psrp stays in ansible-core |
| Feb 2026 | pypsrp 0.9.0 stable (current) |

Both pypsrp and pywinrm are maintained by the same author (jborean93), who also
maintains the `ansible.windows` collection.

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
| Buffering/Piping | Limited | Native PowerShell pipeline support |
| Plugin Location | `ansible.builtin.winrm` | `ansible.builtin.psrp` |
| Python Package | `pywinrm` | `pypsrp` |

## Why PSRP Solves the Forkbomb

The core issue with pywinrm is that **each Ansible task creates a new WinRM shell**
with a fresh NTLM authentication. PSRP instead runs commands within a persistent
**PowerShell Runspace Pool** — a single authenticated connection that multiplexes
multiple commands.

This has cascading benefits:

1. **No per-task auth** → eliminates NTLM flood → no AD lockout risk
2. **Persistent connection** → secret management plugins (KeePassXC, SOPS, 1Password)
   can resolve credentials once per connection, not once per task
3. **Buffering and piping** → PowerShell pipeline operations work natively, no
   serialization overhead
4. **50-65% faster** for repeated operations (community benchmarks)

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

## Benchmark Results (This Project)

50 concurrent connections against same Windows Server 2022 host:

| Metric | pywinrm | pypsrp |
|--------|---------|--------|
| Successes | 9/50 | 24/50 |
| Error type | UNREACHABLE (auth failure) | FAILED (read timeout) |
| **Auth failures** | **41** | **0** |
| **AD lockout risk** | **HIGH** (41 failed NTLM) | **NONE** |

PSRP's remaining failures were SSH tunnel TCP saturation (secondary bottleneck),
not authentication problems. With direct network access, PSRP would likely achieve
higher success rates.

## Configuration

### pywinrm (default)

```yaml
# inventory/hosts.yml
win-target:
  ansible_connection: winrm
  ansible_winrm_transport: ntlm
  ansible_winrm_scheme: https
  ansible_winrm_server_cert_validation: ignore
```

### pypsrp

```yaml
# inventory/hosts.yml
win-target:
  ansible_connection: psrp
  ansible_psrp_auth: ntlm
  ansible_psrp_protocol: https
  ansible_psrp_cert_validation: false
  ansible_psrp_reconnection_retries: 3
```

## When to Use Each

| Scenario | Recommendation |
|----------|---------------|
| Small playbooks (<10 tasks) | Either works |
| Large playbooks (50+ tasks) | pypsrp |
| High forks (>10) | pypsrp |
| Parallel molecule tests | pypsrp |
| CI/CD pipelines | pypsrp |
| Shared AD service accounts | pypsrp (critical) |
| Secret management plugins | pypsrp (connection pooling) |
| Debugging WinRM issues | pywinrm (more verbose logs) |

## Migration

Switch from pywinrm to pypsrp:

```yaml
# Group vars for Windows hosts only
windows:
  vars:
    ansible_connection: psrp
    ansible_psrp_auth: ntlm
    ansible_psrp_protocol: https
    ansible_psrp_cert_validation: false
```

Requires `pip install pypsrp` — the connection plugin is in ansible-core but
the Python library must be installed separately.

## References

- [ansible.builtin.psrp](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/psrp_connection.html) — Official docs
- [pypsrp on GitHub](https://github.com/jborean93/pypsrp) — Python library
- [PR #41729](https://github.com/ansible/ansible/pull/41729) — Original ansible-core PR
- [ansible.windows#597](https://github.com/ansible-collections/ansible.windows/issues/597) — Community performance discussion
