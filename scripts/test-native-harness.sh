#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/gradient-native-harness-test-$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/target"
git -C "$TMP_ROOT/target" init >/dev/null
printf "# Fixture\n" > "$TMP_ROOT/target/README.md"

"$ROOT/scripts/gradient.sh" init --profile solo-frontier "$TMP_ROOT/target" >/dev/null

test -f "$TMP_ROOT/target/.agents/agents/planner.md"
test -f "$TMP_ROOT/target/.claude/agents/planner.md"
test -f "$TMP_ROOT/target/.gradient/harness/resolution.json"

(
  cd "$TMP_ROOT/target"
  ./scripts/gradient.sh resolve >/dev/null
  ./scripts/gradient.sh validate >/dev/null
)

echo "native harness regression passed"
