#!/bin/bash
# Install the Rust CI workflow (fmt + clippy + test + audit) to the current repo.
# Run from the repo root. Idempotent: skips if already up to date.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"

SRC="$TEMPLATES_DIR/ci.yml"
DST="$REPO_ROOT/.github/workflows/ci.yml"

mkdir -p "$(dirname "$DST")"
if [[ -f "$DST" ]] && diff -q "$SRC" "$DST" > /dev/null 2>&1; then
    echo "  Up to date: .github/workflows/ci.yml"
else
    cp "$SRC" "$DST"
    echo "  Installed: .github/workflows/ci.yml"
    echo "Done. Review the diff, commit, and push."
fi