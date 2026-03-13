{
  description = "WinRM Molecule Forkbomb Demo - research project for Ansible WinRM connection exhaustion";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        pythonEnv = pkgs.python314.withPackages (ps: with ps; [
          pip
          setuptools
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Python
            pythonEnv
            uv

            # Dhall
            dhall
            dhall-json
            dhall-yaml
            dhall-lsp-server

            # Secrets
            sops
            age

            # Task runner
            just

            # Utilities
            jq
            yq-go
            shellcheck
          ];

          shellHook = ''
            # Prevent macOS fork safety crash with Ansible
            export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

            # ansible-compat v25 rejects the plural form
            unset ANSIBLE_COLLECTIONS_PATHS 2>/dev/null || true

            # SOPS age key location
            export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

            # XDG cache for nix builds
            export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}"
          '';
        };
      }
    );
}
