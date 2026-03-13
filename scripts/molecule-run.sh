#!/usr/bin/env bash
set -euo pipefail

# Molecule wrapper script.
# Unsets ANSIBLE_COLLECTIONS_PATHS (plural) which ansible-compat v25 rejects.
# The plural form is set by Home Manager's Nix Ansible module.

unset ANSIBLE_COLLECTIONS_PATHS 2>/dev/null || true

export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

exec molecule "$@"
