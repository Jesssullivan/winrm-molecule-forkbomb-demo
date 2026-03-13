set dotenv-load := true
set shell := ["bash", "-euo", "pipefail", "-c"]

project_root := justfile_directory()
ansible_dir := project_root / "ansible"
molecule_run := project_root / "scripts" / "molecule-run.sh"

default:
    @just --list --unsorted

# ── SETUP ──────────────────────────────────────────────────────────

# One-time environment setup: venv, deps, galaxy collections
setup:
    scripts/setup-env.sh

# ── TUNNELS ────────────────────────────────────────────────────────

# Start SSH tunnel to win-target (localhost:15986 → win-target:5986)
tunnel-start:
    scripts/start-tunnel.sh start

# Stop SSH tunnel
tunnel-stop:
    scripts/start-tunnel.sh stop

# Check tunnel status
tunnel-status:
    scripts/start-tunnel.sh status

# ── DHALL ──────────────────────────────────────────────────────────

# Render all Dhall configurations to output/
dhall-render:
    @echo "Rendering Dhall configurations..."
    dhall-to-json --file dhall/render-benchmarks.dhall > dhall/output/benchmark-matrix.json
    dhall-to-yaml --file dhall/render-quotas.dhall > dhall/output/quota-presets.yaml
    dhall-to-json --file dhall/render-roles.dhall > dhall/output/role-manifest.json
    @echo "Done. Output in dhall/output/"

# Typecheck all Dhall files
dhall-typecheck:
    dhall type --file dhall/package.dhall > /dev/null
    dhall type --file dhall/render-benchmarks.dhall > /dev/null
    dhall type --file dhall/render-quotas.dhall > /dev/null
    dhall type --file dhall/render-roles.dhall > /dev/null
    @echo "All Dhall files typecheck OK"

# ── VALIDATION ─────────────────────────────────────────────────────

# Run all validation checks (syntax + lint)
validate: validate-syntax validate-lint

# Ansible syntax check
validate-syntax:
    cd {{ansible_dir}} && ansible-playbook --syntax-check playbooks/site.yml
    cd {{ansible_dir}} && ansible-playbook --syntax-check playbooks/audit-winrm.yml
    cd {{ansible_dir}} && ansible-playbook --syntax-check playbooks/benchmark.yml

# Ansible lint
validate-lint:
    cd {{ansible_dir}} && ansible-lint playbooks/ roles/

# ── DEPLOYMENT ─────────────────────────────────────────────────────

# Full deployment: quotas → cleanup → firewall → IIS
deploy:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Dry run deployment
deploy-check:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff

# Deploy only WinRM quota configuration (admin toggle)
deploy-quotas:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags winrm-quota

# Deploy only WinRM session cleanup
deploy-cleanup:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags winrm-cleanup

# Deploy only IIS site + firewall rules
deploy-iis:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags iis-site,firewall

# Deploy only WinRM monitoring/observability (shell metrics + event log forwarding)
deploy-monitoring:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags winrm-monitoring

# Reset WinRM quotas to Windows defaults (for forkbomb demonstration)
reset-quotas:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags winrm-quota \
      -e winrm_quota_max_shells_per_user=30 \
      -e winrm_quota_max_concurrent_users=10 \
      -e winrm_quota_max_processes_per_shell=25 \
      -e winrm_quota_idle_timeout_ms=7200000 \
      -e winrm_quota_max_memory_per_shell_mb=1024 \
      -e winrm_quota_max_concurrent_ops_per_user=1500

# ── AUDIT & MONITORING ─────────────────────────────────────────────

# Read-only WinRM quota and session audit
audit:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/audit-winrm.yml

# Live WinRM connection monitoring (run in separate terminal)
monitor:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/monitor-connections.yml

# ── MOLECULE ───────────────────────────────────────────────────────

# Run all molecule tests sequentially (safe)
molecule-all: (molecule-role "winrm_quota_config") (molecule-role "winrm_session_cleanup") (molecule-role "firewall_rules") (molecule-role "iis_site")

# Run molecule test for a specific role
molecule-role role:
    cd {{ansible_dir}}/roles/{{role}} && {{molecule_run}} test

# Converge a specific role (apply without destroy)
molecule-converge role:
    cd {{ansible_dir}}/roles/{{role}} && {{molecule_run}} converge

# Verify a specific role
molecule-verify role:
    cd {{ansible_dir}}/roles/{{role}} && {{molecule_run}} verify

# Destroy molecule instances for a role
molecule-destroy role:
    cd {{ansible_dir}}/roles/{{role}} && {{molecule_run}} destroy

# ── BENCHMARKING ───────────────────────────────────────────────────

# Run full benchmark sequence (safe → unsafe → quota fix → retry → psrp)
benchmark:
    scripts/benchmark-forkbomb.sh

# Safe benchmark: forks=5, guaranteed to work with default quotas
benchmark-safe:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/benchmark.yml \
      -e benchmark_forks=5 -e benchmark_label=safe-forks5 -f 5

# Unsafe benchmark: forks=50, demonstrates the forkbomb
benchmark-unsafe:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/benchmark.yml \
      -e benchmark_forks=50 -e benchmark_label=forkbomb-50 -f 50

# PSRP benchmark: forks=20 with pypsrp connection plugin
benchmark-psrp:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/benchmark.yml \
      -e benchmark_forks=20 -e benchmark_label=psrp-forks20 -e ansible_connection=psrp -f 20

# Custom benchmark with specified fork count
benchmark-custom forks:
    cd {{ansible_dir}} && ansible-playbook -i inventory/hosts.yml playbooks/benchmark.yml \
      -e benchmark_forks={{forks}} -e benchmark_label=custom-forks{{forks}} -f {{forks}}

# ── TESTING ────────────────────────────────────────────────────────

# Run all tests (offline, no Windows host needed)
test:
    .venv/bin/pytest -v

# Run structure validation tests only
test-structure:
    .venv/bin/pytest -m structure -v

# Run Dhall validation tests only
test-dhall:
    .venv/bin/pytest -m dhall -v

# ── SECRETS ────────────────────────────────────────────────────────

# Decrypt and display WinRM credentials (for debugging)
decrypt-creds:
    sops -d secrets/winrm-creds.enc.yaml

# Edit WinRM credentials (opens editor, re-encrypts on save)
edit-creds:
    sops secrets/winrm-creds.enc.yaml
