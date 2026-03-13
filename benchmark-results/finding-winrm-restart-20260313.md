# Research Finding: WinRM Service Restart is Destructive Over WinRM

**Date**: 2026-03-13
**Severity**: High (operational risk)

## Observation

Restarting the WinRM service (`Restart-Service WinRM`) from within a WinRM session
causes the connection to drop permanently. The host becomes unreachable via WinRM
until either:

1. The WinRM service is manually restarted from the Windows console/RDP
2. The host is rebooted
3. A snapshot rollback is performed

## Context

During quota reset (`just reset-quotas`), the `winrm_quota_config` role's handler
triggered a WinRM service restart after changing quota values. Despite:

- Using `async: 30` + `poll: 0` to fire-and-forget the restart
- Waiting with retry/delay for WinRM to come back
- Killing and restarting the SSH tunnel
- Waiting 30+ seconds for service recovery

The host remained unreachable with "Connection reset by peer" errors.

## Root Cause Hypothesis

1. WinRM restart kills ALL active WinRM sessions including our management session
2. The restart with restrictive `MaxConcurrentUsers=10` may have changed the service
   behavior during startup
3. The HTTPS listener may not rebind immediately after service restart
4. The SSH tunnel's connection pooling caches a dead TCP state

## Impact on Demo

- Cannot use WinRM to restart WinRM for quota changes
- Quota changes that DON'T trigger WinRM restart work fine
- The handler should be removed or made optional for quota-only changes

## Recommendation

1. **Don't restart WinRM after quota changes** — WSMan quotas take effect immediately
   without a service restart. Remove the `notify: restart winrm` from configure.yml.
2. **If restart is needed**, use a scheduled task that fires after a delay, or use
   RDP/console access.
3. **For the forkbomb demo**: Set quotas WITHOUT restarting WinRM. The values take
   effect on new shell creation, not on existing shells.

## RDP Investigation (15:50 UTC)

Connected via RDP. Findings:

1. `Get-Service WinRM` → **Stopped** (never restarted after our handler)
2. `winrm enumerate winrm/config/listener` → fails (service not running)
3. `Start-Service WinRM` → **FAILS**: "Cannot open WinRM service on computer '.'"
4. Event Log shows Event ID 468901 (Warning) at 15:46 — the exact time our handler fired
5. The event description can't be resolved — suggests service corruption

**`Restart-Service WinRM -Force` left the service in an unrecoverable state.**
`Start-Service` also fails — the service is corrupted, not just stopped.
Only a full OS reboot recovers.

## Root Cause (Updated)

The `-Force` flag on `Restart-Service` kills the service process immediately without
allowing graceful shutdown of the WS-Management stack. This can corrupt the service's
internal state such that:
- The service shows as "Stopped" but cannot be started
- `Start-Service` errors with "Cannot open WinRM service on computer '.'"
- The HTTPS listener binding is lost
- Only an OS reboot resets the service to a known-good state

## Recovery

**Reboot the machine** — `Start-Service WinRM` does not work after this failure:
```powershell
# From RDP or console:
Restart-Computer -Force
```

Quota changes persist in the registry and survive reboot. After reboot, WinRM
will come up with our configured values (MaxShellsPerUser=30, etc.).
