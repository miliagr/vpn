#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v xray >/dev/null || { echo 'xray is required for validation (macOS: brew install xray)' >&2; exit 1; }
for f in "$ROOT/build/server-vps1.json" "$ROOT/build/server-vps2.json"; do
  [[ -f "$f" ]] || { echo "Missing $f; run ./scripts/render.sh first" >&2; exit 1; }
  echo "==> validating $f"
  xray run -test -config "$f"
done
