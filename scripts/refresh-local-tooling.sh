#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v mix >/dev/null 2>&1; then
  echo "thinktank: mix is required to refresh local tooling." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "thinktank: python3 is required for local model validation and Git hooks." >&2
  exit 1
fi

if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
fi

echo "thinktank: refreshing local tooling..."
mix deps.get --quiet
mix escript.build >/dev/null

mkdir -p "${HOME}/.local/bin"
cp ./thinktank "${HOME}/.local/bin/thinktank"

if [ -f dagger.json ] && command -v dagger >/dev/null 2>&1; then
  export DAGGER_NO_NAG=1
  if command -v colima >/dev/null 2>&1; then
    ./scripts/with-colima.sh dagger develop >/dev/null
  fi
fi

echo "thinktank updated: $(./thinktank --version)"
