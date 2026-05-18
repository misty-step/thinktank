#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/gradient-workspace-upgrade-test-$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/target"
git -C "$TMP_ROOT/target" init >/dev/null
printf "# Fixture\n" > "$TMP_ROOT/target/README.md"

"$ROOT/scripts/gradient.sh" init --profile solo-frontier "$TMP_ROOT/target" >/dev/null
"$ROOT/scripts/gradient.sh" upgrade --dry-run "$TMP_ROOT/target" >/dev/null
"$ROOT/scripts/gradient.sh" upgrade --apply "$TMP_ROOT/target" >/dev/null

(
  cd "$TMP_ROOT/target"
  ./scripts/gradient.sh validate >/dev/null
)

echo "workspace upgrade regression passed"
