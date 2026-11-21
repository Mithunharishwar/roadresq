#!/usr/bin/env bash
# Reproduce the CI checks locally: static analysis, backend tests, function syntax.
# Mirrors .github/workflows/ci.yml — run this before pushing.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> flutter analyze"
flutter analyze

echo "==> backend tests"
(
  cd backend
  if [ -x .venv/bin/python ]; then
    .venv/bin/python -m pytest tests -q
  else
    python -m pytest tests -q
  fi
)

echo "==> cloud functions syntax"
(
  cd functions
  for f in *.js; do
    node --check "$f"
  done
)

echo "All checks passed."
