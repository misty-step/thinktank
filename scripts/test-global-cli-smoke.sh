#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/gradient-global-cli-smoke-test-$$"

cleanup() {
  chmod -R u+w "$TMP_ROOT" 2>/dev/null || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/external" "$TMP_ROOT/target"
git -C "$TMP_ROOT/external" init >/dev/null
git -C "$TMP_ROOT/target" init >/dev/null
printf "# External\n" > "$TMP_ROOT/external/README.md"
printf "# Target\n" > "$TMP_ROOT/target/README.md"

(
  cd "$TMP_ROOT/external"
  export HOME="$TMP_ROOT/home"
  export GRADIENT_CONFIG_DIR="$TMP_ROOT/home/.gradient"
  export PATH="$ROOT/bin:$PATH"

  command -v gradient >/dev/null
  gradient status > "$TMP_ROOT/status.out"
  gradient config > "$TMP_ROOT/config.out"
  gradient init --profile solo-frontier "$TMP_ROOT/target" > "$TMP_ROOT/init.out"
)

grep -q "Gradient core: $ROOT" "$TMP_ROOT/status.out"
grep -q "core_root: $ROOT" "$TMP_ROOT/config.out"
test -f "$TMP_ROOT/target/gradient.yaml"
test -f "$TMP_ROOT/target/.gradient/harness/resolution.json"
test -f "$TMP_ROOT/target/backlog.d/001-gradient-onboarding.md"

echo "global cli smoke regression passed"
