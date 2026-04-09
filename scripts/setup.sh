#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v mix >/dev/null 2>&1; then
  echo "mix is required to bootstrap thinktank." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for local model validation and Git hooks." >&2
  exit 1
fi

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example."
fi

chmod +x .githooks/* scripts/refresh-local-tooling.sh
git config core.hooksPath .githooks

mix deps.get
mix escript.build
./thinktank --help >/dev/null

if command -v dagger >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  export DAGGER_NO_NAG=1
  dagger develop >/dev/null
  dagger call check
else
  mix compile --warnings-as-errors
  mix test
fi

echo "Setup complete."
echo "Git hooks installed from .githooks via core.hooksPath."
echo "Add THINKTANK_OPENROUTER_API_KEY to .env or your shell before live model runs."
