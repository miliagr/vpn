#!/usr/bin/env bash
# Runs every tests/test_*.sh. None of them touch real servers or read .env.local.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$DIR"/test_*.sh; do
  echo "== $(basename "$t")"
  bash "$t" || rc=1
done
[[ $rc -eq 0 ]] && echo 'ALL TESTS PASSED' || echo 'TESTS FAILED' >&2
exit $rc
