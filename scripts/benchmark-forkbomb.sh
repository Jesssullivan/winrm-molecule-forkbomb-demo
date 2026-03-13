#!/usr/bin/env bash
set -euo pipefail

# Full WinRM forkbomb benchmark sequence.
# Reads benchmark profiles from Dhall-generated matrix when available,
# otherwise falls back to hardcoded sequence.
#
# Demonstrates the connection exhaustion problem and validates the fix.
#
# Sequence:
#   1. Audit baseline WinRM state
#   2. Run all benchmark profiles from Dhall matrix (or hardcoded fallback)
#   3. Apply quota elevation (admin toggle fix)
#   4. Re-run expected-failure profiles (should now succeed)
#   5. PSRP comparison profiles
#   6. Session cleanup + final audit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
RESULTS_DIR="${PROJECT_ROOT}/benchmark-results"
DHALL_MATRIX="${PROJECT_ROOT}/dhall/output/benchmark-matrix.json"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="${RESULTS_DIR}/run_${TIMESTAMP}.log"

mkdir -p "$RESULTS_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$RESULT_FILE"
}

run_playbook() {
    local label="$1"
    shift
    log "── ${label} ──"
    local start_time
    start_time=$(date +%s)

    if cd "$ANSIBLE_DIR" && ansible-playbook -i inventory/hosts.yml "$@" 2>&1 | tee -a "$RESULT_FILE"; then
        local end_time
        end_time=$(date +%s)
        log "PASS ${label} completed in $((end_time - start_time))s"
        return 0
    else
        local end_time
        end_time=$(date +%s)
        log "FAIL ${label} FAILED after $((end_time - start_time))s"
        return 1
    fi
}

run_benchmark_profile() {
    local name="$1"
    local forks="$2"
    local connection="$3"
    local expect_failure="$4"
    local serial_val="${5:-}"

    local extra_args=(-e "benchmark_forks=${forks}" -e "benchmark_label=${name}" -f "${forks}")

    if [[ "$connection" == "psrp" ]]; then
        extra_args+=(-e "ansible_connection=psrp")
    fi

    if [[ -n "$serial_val" && "$serial_val" != "null" ]]; then
        extra_args+=(-e "serial=${serial_val}")
    fi

    if [[ "$expect_failure" == "true" ]]; then
        run_playbook "Profile: ${name} (forks=${forks}, ${connection}, expect_failure=true)" \
            playbooks/benchmark.yml "${extra_args[@]}" || true
    else
        run_playbook "Profile: ${name} (forks=${forks}, ${connection})" \
            playbooks/benchmark.yml "${extra_args[@]}"
    fi
}

log "╔══════════════════════════════════════════════════╗"
log "║  WinRM Forkbomb Benchmark Suite                 ║"
log "║  Started: $(date '+%Y-%m-%d %H:%M:%S')                  ║"
log "╚══════════════════════════════════════════════════╝"
log ""

# Step 1: Audit baseline
run_playbook "Step 1: Baseline Audit" playbooks/audit-winrm.yml

# Step 2: Run benchmark profiles
if [[ -f "$DHALL_MATRIX" ]]; then
    log "Reading benchmark profiles from Dhall matrix: ${DHALL_MATRIX}"
    profile_count=$(jq length "$DHALL_MATRIX")
    log "Found ${profile_count} profiles"

    # Phase A: Run WinRM profiles (before quota elevation)
    log ""
    log "=== Phase A: WinRM profiles with current quotas ==="
    jq -c '.[] | select(.connection_plugin == "winrm")' "$DHALL_MATRIX" | while read -r profile; do
        name=$(echo "$profile" | jq -r '.name')
        forks=$(echo "$profile" | jq -r '.forks')
        connection=$(echo "$profile" | jq -r '.connection_plugin')
        expect_failure=$(echo "$profile" | jq -r '.expect_failure')
        serial_val=$(echo "$profile" | jq -r '.serial // "null"')

        run_benchmark_profile "$name" "$forks" "$connection" "$expect_failure" "$serial_val"
    done

    # Phase B: Apply quota elevation
    log ""
    log "=== Phase B: Applying quota elevation (the fix) ==="
    run_playbook "Quota Elevation" playbooks/site.yml --tags winrm-quota

    # Phase C: Re-run expected-failure profiles (should now succeed)
    log ""
    log "=== Phase C: Re-run failure profiles with elevated quotas ==="
    jq -c '.[] | select(.expect_failure == true)' "$DHALL_MATRIX" | while read -r profile; do
        name=$(echo "$profile" | jq -r '.name')
        forks=$(echo "$profile" | jq -r '.forks')
        connection=$(echo "$profile" | jq -r '.connection_plugin')
        serial_val=$(echo "$profile" | jq -r '.serial // "null"')

        run_benchmark_profile "${name}-elevated" "$forks" "$connection" "false" "$serial_val"
    done

    # Phase D: PSRP comparison profiles
    log ""
    log "=== Phase D: PSRP comparison profiles ==="
    jq -c '.[] | select(.connection_plugin == "psrp")' "$DHALL_MATRIX" | while read -r profile; do
        name=$(echo "$profile" | jq -r '.name')
        forks=$(echo "$profile" | jq -r '.forks')
        connection=$(echo "$profile" | jq -r '.connection_plugin')
        expect_failure=$(echo "$profile" | jq -r '.expect_failure')
        serial_val=$(echo "$profile" | jq -r '.serial // "null"')

        run_benchmark_profile "$name" "$forks" "$connection" "$expect_failure" "$serial_val"
    done
else
    log "No Dhall matrix found at ${DHALL_MATRIX}, using hardcoded fallback"
    log "Run 'just dhall-render' first for data-driven benchmarks"
    log ""

    # Fallback: hardcoded sequence
    run_playbook "Safe Benchmark (forks=5)" \
        playbooks/benchmark.yml -e benchmark_forks=5 -e benchmark_label=safe-5 -f 5

    run_playbook "Moderate Benchmark (forks=10)" \
        playbooks/benchmark.yml -e benchmark_forks=10 -e benchmark_label=moderate-10 -f 10

    log ""
    log "WARNING: Next step may fail - this demonstrates the forkbomb behavior"
    run_playbook "FORKBOMB (forks=50)" \
        playbooks/benchmark.yml -e benchmark_forks=50 -e benchmark_label=forkbomb-50 -f 50 || true

    run_playbook "Quota Elevation" playbooks/site.yml --tags winrm-quota

    run_playbook "Forkbomb with Elevated Quotas (forks=50)" \
        playbooks/benchmark.yml -e benchmark_forks=50 -e benchmark_label=elevated-50 -f 50

    run_playbook "PSRP Comparison (forks=20)" \
        playbooks/benchmark.yml -e benchmark_forks=20 -e benchmark_label=psrp-20 -e ansible_connection=psrp -f 20 || true
fi

# Final steps
log ""
log "=== Final: Session cleanup and audit ==="
run_playbook "Session Cleanup" playbooks/site.yml --tags winrm-cleanup || true

run_playbook "Post-Benchmark Audit" playbooks/audit-winrm.yml

log ""
log "╔══════════════════════════════════════════════════╗"
log "║  Benchmark Complete                             ║"
log "║  Results: ${RESULT_FILE}"
log "╚══════════════════════════════════════════════════╝"
