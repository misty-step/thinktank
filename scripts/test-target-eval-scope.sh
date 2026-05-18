#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/gradient-target-eval-scope-test-$$"

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
  mkdir -p agent-primitives
  cp -R .agents/skills agent-primitives/skills
  perl -0pi -e 's#shared_skill_root: \.agents/skills#shared_skill_root: agent-primitives/skills#' gradient.yaml
  ./scripts/gradient.sh resolve >/dev/null
  grep -q '"shared_skill_root": "agent-primitives/skills"' .gradient/harness/resolution.json
  ./scripts/gradient.sh capture backlog.d/001-gradient-onboarding.md >/dev/null
  ./scripts/gradient.sh eval > "$TMP_ROOT/target-eval.out"
  grep -q "SKIP core workspace regressions: current repo is an initialized target workspace" "$TMP_ROOT/target-eval.out"
)

echo "target eval scope regression passed"
