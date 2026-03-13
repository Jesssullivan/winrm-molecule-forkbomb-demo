"""Shared fixtures for winrm-forkbomb-demo tests."""

import json
from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).parent.parent
ANSIBLE_DIR = PROJECT_ROOT / "ansible"
ROLES_DIR = ANSIBLE_DIR / "roles"
DHALL_DIR = PROJECT_ROOT / "dhall"


@pytest.fixture
def project_root():
    return PROJECT_ROOT


@pytest.fixture
def ansible_dir():
    return ANSIBLE_DIR


@pytest.fixture
def roles_dir():
    return ROLES_DIR


@pytest.fixture
def dhall_dir():
    return DHALL_DIR


@pytest.fixture
def role_names():
    """List of all role directory names."""
    return [d.name for d in ROLES_DIR.iterdir() if d.is_dir() and not d.name.startswith(".")]


def load_yaml(path: Path) -> dict:
    """Load a YAML file and return its contents."""
    with open(path) as f:
        return yaml.safe_load(f)


def load_json(path: Path) -> dict:
    """Load a JSON file and return its contents."""
    with open(path) as f:
        return json.load(f)
