# Changelog

Every commit must update this file (enforced by `.githooks/pre-commit`; enable with `./scripts/install-hooks.sh`). Never put UUIDs, keys, short IDs or VLESS links here.

## Unreleased

### Added
- NixOS as the primary target: `flake.nix`, `nix/` (common, disko disk layout, Xray unit), `hosts/hosts.json` as the single host list. See `docs/nixos.md`.
- `scripts/nix-validate.sh`, `nix-install.sh`, `nix-push-secrets.sh`, `nix-check.sh`, `nix-deploy.sh`.
- Test suite in `tests/` (`tests/run.sh`): static checks, secret hygiene, and script runs with a fake `xray` including a third host. `tests/test_nix.sh` evaluates all hosts when Nix is installed.
- Pre-commit hook that runs the tests and requires a changelog entry plus docs for behaviour changes; `scripts/install-hooks.sh`.
- `CLAUDE.md` with project rules for Claude.

### Changed
- `generate-secrets.sh` and `make-mobile-profiles.sh` iterate over `hosts/hosts.json` instead of a hard-coded vps1/vps2.
- `preflight.sh` also checks `jq` and reports whether `nix` is present.
- Legacy Ubuntu scripts (`render`, `validate`, `deploy`, `check-server`) kept, vps1/vps2 only.
