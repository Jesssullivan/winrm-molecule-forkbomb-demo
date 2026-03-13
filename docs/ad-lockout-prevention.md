# Active Directory Lockout Prevention

## How AD Lockout Happens from WinRM

1. WinRM quota exhaustion → shell creation fails
2. Error message: "credentials rejected" (misleading - creds are fine)
3. Ansible retries authentication automatically
4. Each retry = failed NTLM attempt recorded by AD
5. AD lockout threshold (typically 5 failures in 15 min) triggers
6. Account locked → ALL hosts using that account lose access

## Prevention Checklist

### Before Running Parallel Tests

- [ ] Run `just audit` to check current quota state
- [ ] Run `just deploy-quotas` if quotas are at Windows defaults
- [ ] Verify tunnel is active: `just tunnel-status`
- [ ] Start in a separate terminal: `just monitor`

### During Testing

- [ ] Watch for "credentials rejected" errors - **STOP IMMEDIATELY**
- [ ] Do NOT retry failed playbooks without checking quota state
- [ ] Use `just benchmark-safe` before `just benchmark-unsafe`

### After an Incident

1. **STOP all automation immediately**
2. Check if account is locked: `Get-ADUser -Identity svc-ansible -Properties LockedOut`
3. Unlock if needed: `Unlock-ADAccount -Identity svc-ansible` (requires Domain Admin)
4. Wait for lockout duration to expire (typically 15-30 min)
5. Run `just audit` to verify quotas
6. Run `just deploy-quotas` to elevate quotas
7. Resume with `just benchmark-safe` first

## Key Rules

1. **NEVER** retry after "credentials rejected" without checking quotas
2. **ALWAYS** run quota audit before parallel testing
3. **ALWAYS** use `serial: 1` for molecule converge plays
4. **PREFER** pypsrp over pywinrm for production automation
5. **MONITOR** connections during benchmark runs

## AD Lockout Policy (Typical)

| Setting | Typical Value |
|---------|---------------|
| Lockout Threshold | 5 failed attempts |
| Lockout Duration | 30 minutes |
| Reset Counter After | 15 minutes |
| Observation Window | 15 minutes |

## Shared Account Risk

All managed Windows hosts share the `svc-ansible` AD account. One lockout = all hosts locked.
This is the primary risk factor for the forkbomb scenario.
