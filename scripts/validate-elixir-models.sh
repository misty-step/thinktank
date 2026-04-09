#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "thinktank: python3 is required for live model-ID validation." >&2
  exit 1
fi

exec python3 "$SCRIPT_DIR/validate_elixir_models.py" --repo-root "$REPO_ROOT" "$@"
