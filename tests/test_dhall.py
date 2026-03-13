"""Dhall output validation tests.

These tests verify that Dhall configurations typecheck and render correctly.
Requires dhall and dhall-to-json to be available in PATH.
"""

import json
import subprocess
from pathlib import Path

import pytest

from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
DHALL_DIR = PROJECT_ROOT / "dhall"

EXPECTED_ROLES = [
    "winrm_quota_config",
    "winrm_session_cleanup",
    "iis_site",
    "firewall_rules",
    "winrm_monitoring",
]


def dhall_to_json(dhall_file: Path) -> dict:
    """Render a Dhall file to JSON."""
    result = subprocess.run(
        ["dhall-to-json", "--file", str(dhall_file)],
        capture_output=True,
        text=True,
        cwd=PROJECT_ROOT,
    )
    if result.returncode != 0:
        pytest.fail(f"dhall-to-json failed for {dhall_file}: {result.stderr}")
    return json.loads(result.stdout)


def dhall_typecheck(dhall_file: Path) -> bool:
    """Typecheck a Dhall file."""
    result = subprocess.run(
        ["dhall", "type", "--file", str(dhall_file)],
        capture_output=True,
        text=True,
        cwd=PROJECT_ROOT,
    )
    return result.returncode == 0


@pytest.mark.dhall
class TestDhallTypecheck:
    """Verify all Dhall files typecheck."""

    DHALL_FILES = [
        "package.dhall",
        "hosts.dhall",
        "quotas.dhall",
        "benchmarks.dhall",
        "roles.dhall",
        "render-benchmarks.dhall",
        "render-quotas.dhall",
        "render-roles.dhall",
    ]

    @pytest.mark.parametrize("dhall_file", DHALL_FILES)
    def test_typecheck(self, dhall_file):
        path = DHALL_DIR / dhall_file
        assert path.exists(), f"Missing Dhall file: {path}"
        assert dhall_typecheck(path), f"Typecheck failed: {path}"


@pytest.mark.dhall
class TestBenchmarkMatrix:
    """Verify the benchmark matrix contains expected profiles."""

    def test_render_succeeds(self):
        data = dhall_to_json(DHALL_DIR / "render-benchmarks.dhall")
        assert isinstance(data, list)
        assert len(data) >= 5, "Expected at least 5 benchmark profiles"

    def test_has_serial_safe(self):
        data = dhall_to_json(DHALL_DIR / "render-benchmarks.dhall")
        names = [p["name"] for p in data]
        assert "serial-safe" in names

    def test_has_forkbomb(self):
        data = dhall_to_json(DHALL_DIR / "render-benchmarks.dhall")
        names = [p["name"] for p in data]
        assert "forkbomb-50" in names

    def test_has_psrp_profile(self):
        data = dhall_to_json(DHALL_DIR / "render-benchmarks.dhall")
        psrp_profiles = [p for p in data if p["connection_plugin"] == "psrp"]
        assert len(psrp_profiles) >= 1

    def test_forkbomb_expects_failure(self):
        data = dhall_to_json(DHALL_DIR / "render-benchmarks.dhall")
        forkbomb = next(p for p in data if p["name"] == "forkbomb-50")
        assert forkbomb["expect_failure"] is True


@pytest.mark.dhall
class TestQuotaPresets:
    """Verify quota presets have valid values."""

    def test_render_succeeds(self):
        data = dhall_to_json(DHALL_DIR / "render-quotas.dhall")
        assert "windows_default" in data
        assert "safe" in data
        assert "stress" in data

    def test_default_matches_windows(self):
        data = dhall_to_json(DHALL_DIR / "render-quotas.dhall")
        default = data["windows_default"]
        assert default["maxShellsPerUser"] == 30
        assert default["maxConcurrentUsers"] == 10

    def test_safe_higher_than_default(self):
        data = dhall_to_json(DHALL_DIR / "render-quotas.dhall")
        default = data["windows_default"]
        safe = data["safe"]
        assert safe["maxShellsPerUser"] > default["maxShellsPerUser"]
        assert safe["maxConcurrentUsers"] > default["maxConcurrentUsers"]

    def test_stress_higher_than_safe(self):
        data = dhall_to_json(DHALL_DIR / "render-quotas.dhall")
        safe = data["safe"]
        stress = data["stress"]
        assert stress["maxShellsPerUser"] > safe["maxShellsPerUser"]


@pytest.mark.dhall
class TestRoleManifest:
    """Verify role manifest matches actual roles."""

    def test_render_succeeds(self):
        data = dhall_to_json(DHALL_DIR / "render-roles.dhall")
        assert isinstance(data, list)
        assert len(data) == len(EXPECTED_ROLES)

    def test_all_roles_present(self):
        data = dhall_to_json(DHALL_DIR / "render-roles.dhall")
        names = [r["name"] for r in data]
        for role in EXPECTED_ROLES:
            assert role in names, f"Role {role} missing from manifest"

    def test_phases_ordered(self):
        data = dhall_to_json(DHALL_DIR / "render-roles.dhall")
        phases = [r["phase"] for r in data]
        assert phases == sorted(phases), "Roles should be ordered by phase"
