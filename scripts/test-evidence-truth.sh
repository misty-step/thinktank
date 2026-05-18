#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/gradient-evidence-truth-test-$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/target"
git -C "$TMP_ROOT/target" init >/dev/null
printf "# Fixture\n" > "$TMP_ROOT/target/README.md"

"$ROOT/scripts/gradient.sh" init --profile solo-frontier "$TMP_ROOT/target" >/dev/null

(
  cd "$TMP_ROOT/target"
  ./scripts/gradient.sh capture backlog.d/001-gradient-onboarding.md >/dev/null
  ./scripts/gradient.sh validate >/dev/null
  ./scripts/gradient.sh report --latest >/dev/null
)

echo "evidence truth regression passed"
