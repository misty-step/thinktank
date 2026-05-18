#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/gradient-readiness-test-$$"

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
  before_count="$(find backlog.d -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' | wc -l | tr -d ' ')"
  ./scripts/gradient.sh readiness >"$TMP_ROOT/readiness.out"
  grep -q "Category Scores" "$TMP_ROOT/readiness.out"
  ./scripts/gradient.sh readiness --route backlog >/dev/null
  after_count="$(find backlog.d -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' | wc -l | tr -d ' ')"
  test "$after_count" -gt "$before_count"
  test -n "$(find .gradient/readiness -maxdepth 1 -type f -name 'readiness-*.json' -print -quit)"
  test -n "$(find .gradient/readiness -maxdepth 1 -type f -name 'readiness-*.md' -print -quit)"
)

echo "readiness report regression passed"
