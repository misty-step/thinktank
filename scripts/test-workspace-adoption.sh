#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/gradient-workspace-adoption-test-$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/target/backlog.d"
git -C "$TMP_ROOT/target" init >/dev/null
printf "# Fixture\n" > "$TMP_ROOT/target/README.md"
printf "# Existing Ticket\n\n## Oracle\n\n- [ ] Preserve the original body.\n" > "$TMP_ROOT/target/backlog.d/003-existing-ticket.md"

"$ROOT/scripts/gradient.sh" init --profile solo-frontier "$TMP_ROOT/target" >/dev/null

(
  cd "$TMP_ROOT/target"
  ./scripts/gradient.sh work adopt backlog.d >/dev/null
  grep -q "Preserve the original body." backlog.d/003-existing-ticket.md
  ./scripts/gradient.sh feedback report "Synthetic feedback route" >/dev/null
  ./scripts/gradient.sh feedback list >/dev/null
  ./scripts/gradient.sh resolve >/dev/null
  ./scripts/gradient.sh validate >/dev/null
)

echo "workspace adoption regression passed"
