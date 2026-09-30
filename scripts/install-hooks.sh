#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
git config core.hooksPath .githooks
echo 'Git hooks enabled (.githooks/pre-commit: tests + changelog/docs check).'
