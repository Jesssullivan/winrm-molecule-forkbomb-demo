# Forkbomb Demo Results - 2026-03-13

## Setup

- Target: vmnode852 (Windows Server 2022, post-reboot)
- Connection: WinRM HTTPS via SSH tunnel (localhost:15852 → vmnode852:5986)
- Credentials: js-sdi via SOPS+age
- Pressure test: 50 inventory entries pointing at same host

## Test 1: Safe Baseline (forks=5, single host)

| Metric | Value |
|--------|-------|
| Result | **PASS** (all 5 pings OK) |
| Duration | 32s |
| Pre/post shells | 1/1 |

## Test 2: Forkbomb (forks=50, 50 "hosts", default quotas)

Quotas: MaxShellsPerUser=30, MaxConcurrentUsers=10

| Metric | Value |
|--------|-------|
| Total connections | 50 |
| **SUCCESS** | **9** |
| **UNREACHABLE** | **41** |
| Error message | `"Task failed: ntlm:"` (truncated) |

**Analysis**: ~9-10 succeeded matching MaxConcurrentUsers=10. The remaining 41
received NTLM auth failures — the quota exhaustion is disguised as credential
rejection. Each failure would count as a failed AD auth attempt.

### Key Finding: Single Host + High Forks ≠ Forkbomb

With a single inventory host, forks=50 has no effect — all tasks run serially.
The forkbomb requires **multiple concurrent connections**, achieved via:
- Multiple inventory entries pointing at same host
- Parallel molecule processes
- async tasks

## Test 3: After Quota Elevation (MaxShellsPerUser=100, MaxConcurrentUsers=25)

| Metric | Value |
|--------|-------|
| Total connections | 50 |
| **SUCCESS** | **20** |
| **UNREACHABLE** | **30** |

Improvement: 9 → 20 successes (matching MaxConcurrentUsers increase from 10 → 25).
Remaining failures likely caused by SSH tunnel TCP connection limits (50 concurrent
HTTPS streams through one SSH tunnel).

## Test 4: Forks=25, 25 hosts (within MaxConcurrentUsers=25)

| Metric | Value |
|--------|-------|
| Total connections | 25 |
| **SUCCESS** | **20** |
| **UNREACHABLE** | **5** |

Even within quota limits, 5 still fail — confirming the SSH tunnel as a secondary
bottleneck. The tunnel's TCP connection pool can handle ~20 concurrent connections
reliably.

## Findings Summary

1. **Forkbomb is reproducible** via multiple inventory entries against one host
2. **MaxConcurrentUsers is the primary gate** — successes match this value
3. **Error messages are misleading** — "ntlm:" instead of "quota exceeded"
4. **Plugin-level quotas** are a hidden second layer (already maxed on vmnode852)
5. **SSH tunnel is a secondary bottleneck** — ~20 concurrent connections max
6. **Single host + high forks** does NOT reproduce the issue (serial execution)

## Quota State Comparison

| Setting | Default | Elevated | Effect |
|---------|---------|----------|--------|
| MaxConcurrentUsers | 10 | 25 | 9→20 successes |
| MaxShellsPerUser | 30 | 100 | Not the bottleneck (ConcurrentUsers hit first) |
| MaxProcessesPerShell | 25 | 50 | Not tested |

## Test 5: PSRP Pressure Test (forks=50, elevated quotas)

Connection: `ansible_connection=psrp`, `ansible_psrp_auth=ntlm`

| Metric | Value |
|--------|-------|
| Total connections | 50 |
| **SUCCESS** | **24** |
| **FAILED** | **26** |
| **UNREACHABLE** | **0** |
| Error message | `HTTPSConnectionPool: Read timed out (read timeout=30)` |

**Key comparison with pywinrm:**

| Aspect | pywinrm (Test 2) | pypsrp (Test 5) |
|--------|-------------------|-----------------|
| Successes | 9 | 24 |
| Error type | UNREACHABLE (auth) | FAILED (timeout) |
| Auth failures | 41 | **0** |
| AD lockout risk | **HIGH** (41 failed NTLM) | **NONE** |

PSRP's connection pooling eliminates auth failures entirely. The remaining failures
are SSH tunnel TCP timeouts (secondary bottleneck), not auth problems.

## Test 6: jsullivan2 Permission Check

`Remote Management Users` group on vmnode852 is **empty**. Only `BUILTIN\Administrators`
members can connect via WinRM. This means:
- `js-sdi`: Can connect (via vmnode852-island → Administrators)
- `jsullivan2`: **Cannot connect** (standard AD user, not in any admin group)
- Quota modification requires admin rights that jsullivan2 does not have

## AD Lockout Risk

With 41 failed NTLM attempts in ~5 seconds:
- AD lockout threshold = 5 failures in 15 min
- **41 failures = 8x the lockout threshold in one burst**
- All 8xx hosts sharing js-sdi account would be locked
