"""Repository structure validation tests.

These tests verify the project follows the expected structure
without requiring a Windows host or network access.
"""

import re
from pathlib import Path

import pytest

from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).parent.parent
ANSIBLE_DIR = PROJECT_ROOT / "ansible"
ROLES_DIR = ANSIBLE_DIR / "roles"


def load_yaml(path: Path) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)

EXPECTED_ROLES = [
    "winrm_quota_config",
    "winrm_session_cleanup",
    "iis_site",
    "firewall_rules",
    "winrm_monitoring",
]

REQUIRED_ROLE_FILES = [
    "defaults/main.yml",
    "tasks/main.yml",
    "meta/main.yml",
]

REQUIRED_MOLECULE_FILES = [
    "molecule/default/molecule.yml",
    "molecule/default/converge.yml",
    "molecule/default/verify.yml",
]


@pytest.mark.structure
class TestRoleStructure:
    """Verify all roles have the required directory structure."""

    @pytest.mark.parametrize("role_name", EXPECTED_ROLES)
    def test_role_exists(self, role_name):
        role_dir = ROLES_DIR / role_name
        assert role_dir.is_dir(), f"Role directory missing: {role_dir}"

    @pytest.mark.parametrize("role_name", EXPECTED_ROLES)
    @pytest.mark.parametrize("required_file", REQUIRED_ROLE_FILES)
    def test_role_has_required_files(self, role_name, required_file):
        path = ROLES_DIR / role_name / required_file
        assert path.is_file(), f"Missing: {path}"

    @pytest.mark.parametrize("role_name", EXPECTED_ROLES)
    @pytest.mark.parametrize("molecule_file", REQUIRED_MOLECULE_FILES)
    def test_role_has_molecule_scenario(self, role_name, molecule_file):
        path = ROLES_DIR / role_name / molecule_file
        assert path.is_file(), f"Missing: {path}"

    @pytest.mark.parametrize("role_name", EXPECTED_ROLES)
    def test_molecule_converge_uses_serial(self, role_name):
        """Verify all molecule converge plays use serial: 1 for WinRM safety."""
        converge = ROLES_DIR / role_name / "molecule/default/converge.yml"
        content = converge.read_text()
        assert "serial:" in content, (
            f"{role_name}/converge.yml missing serial directive - "
            "required for WinRM safety"
        )


@pytest.mark.structure
class TestPlaybookStructure:
    """Verify playbooks exist and are valid YAML."""

    EXPECTED_PLAYBOOKS = [
        "playbooks/site.yml",
        "playbooks/audit-winrm.yml",
        "playbooks/benchmark.yml",
        "playbooks/monitor-connections.yml",
    ]

    @pytest.mark.parametrize("playbook", EXPECTED_PLAYBOOKS)
    def test_playbook_exists(self, playbook):
        path = ANSIBLE_DIR / playbook
        assert path.is_file(), f"Missing playbook: {path}"

    @pytest.mark.parametrize("playbook", EXPECTED_PLAYBOOKS)
    def test_playbook_valid_yaml(self, playbook):
        path = ANSIBLE_DIR / playbook
        data = load_yaml(path)
        assert data is not None, f"Empty or invalid YAML: {path}"


@pytest.mark.structure
class TestNoPlaintextSecrets:
    """Ensure no plaintext secrets are committed."""

    SECRET_PATTERNS = [
        re.compile(r"password:\s+(?!.*\{\{)(?!.*ENC\[)(?!PLACEHOLDER)\S+", re.IGNORECASE),
    ]

    def _check_file(self, path: Path):
        if path.suffix not in (".yml", ".yaml"):
            return
        if "enc" in path.name or ".sops." in path.name:
            return
        content = path.read_text()
        for pattern in self.SECRET_PATTERNS:
            matches = pattern.findall(content)
            for match in matches:
                if "lookup(" in match or "vault" in match.lower():
                    continue
                pytest.fail(f"Potential plaintext secret in {path}: {match}")

    def test_no_plaintext_in_inventory(self):
        for path in (ANSIBLE_DIR / "inventory").rglob("*.yml"):
            self._check_file(path)

    def test_no_plaintext_in_roles(self):
        for path in ROLES_DIR.rglob("*.yml"):
            self._check_file(path)


@pytest.mark.structure
class TestProjectFiles:
    """Verify essential project files exist."""

    REQUIRED_FILES = [
        "flake.nix",
        ".envrc",
        "pyproject.toml",
        ".sops.yaml",
        "justfile",
        "ansible/ansible.cfg",
        "ansible/requirements.yml",
        "ansible/inventory/hosts.yml",
        "ansible/molecule/inventory.yml",
    ]

    @pytest.mark.parametrize("filepath", REQUIRED_FILES)
    def test_file_exists(self, filepath):
        path = PROJECT_ROOT / filepath
        assert path.is_file(), f"Missing: {path}"
