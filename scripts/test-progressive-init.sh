#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/gradient-progressive-init-test-$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/target"
git -C "$TMP_ROOT/target" init >/dev/null
printf "# Fixture\n" > "$TMP_ROOT/target/README.md"
printf "# Existing Agents\n" > "$TMP_ROOT/target/AGENTS.md"
mkdir -p "$TMP_ROOT/target/.agents/skills/custom"
printf "# Custom\n" > "$TMP_ROOT/target/.agents/skills/custom/SKILL.md"

go build -o "$TMP_ROOT/gradient" "$ROOT/cmd/gradient"
"$TMP_ROOT/gradient" init repo --profile solo-frontier "$TMP_ROOT/target" >/dev/null

test -f "$TMP_ROOT/target/AGENTS.md"
test -f "$TMP_ROOT/target/AGENTS.gradient.md"
test -f "$TMP_ROOT/target/.agents/skills/custom/SKILL.md"
test -f "$TMP_ROOT/target/.agents/skills/gradient/SKILL.md"
test -f "$TMP_ROOT/target/.agents/skills/repo-workflow/SKILL.md"
test -f "$TMP_ROOT/target/.agents/agents/repo-guide.md"
test -e "$TMP_ROOT/target/.claude/skills/repo-workflow"
test -e "$TMP_ROOT/target/.claude/agents/repo-guide.md"
test -f "$TMP_ROOT/target/.gradient/init/repo-scan.json"
test -f "$TMP_ROOT/target/.gradient/harness/resolution.json"
test ! -d "$TMP_ROOT/target/backlog.d"
grep -q "adoption_level: harness" "$TMP_ROOT/target/gradient.yaml"
grep -q "repo-workflow" "$TMP_ROOT/target/gradient.yaml"
grep -q "repo-guide" "$TMP_ROOT/target/gradient.yaml"
grep -q "Docs: README.md, AGENTS.md" "$TMP_ROOT/target/AGENTS.gradient.md"

(
  cd "$TMP_ROOT/target"
  "$TMP_ROOT/gradient" resolve >/dev/null
  "$TMP_ROOT/gradient" validate >/dev/null
)

echo "progressive init regression passed"
