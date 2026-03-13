#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Setting up winrm-forkbomb-demo development environment..."

# Create venv if it doesn't exist
if [ ! -d .venv ]; then
    echo "Creating Python virtual environment..."
    uv venv .venv --python 3.14
fi

# Activate venv
source .venv/bin/activate

# Install project dependencies
echo "Installing Python dependencies..."
uv pip install -e ".[test]"

# Install Ansible Galaxy collections
echo "Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections --force

echo ""
echo "Setup complete. Next steps:"
echo "  1. direnv allow          # Activate environment"
echo "  2. sops secrets/winrm-creds.enc.yaml  # Configure credentials"
echo "  3. just tunnel-start     # Start SSH tunnel"
echo "  4. just audit            # Verify connectivity"
