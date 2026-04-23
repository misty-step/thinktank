#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/scripts/ci/gate-policy.sh"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=1
}

emit_matches() {
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "      $line" >&2
  done <<<"$1"
}

check_dynamic_eval() {
  local output
  output="$(rg -nH "$CI_POLICY_DYNAMIC_EXECUTION_API_PATTERN" "$@" || true)"

  if [[ -n "$output" ]]; then
    fail "security-sensitive dynamic execution API detected"
    emit_matches "$output"
  fi
}

check_shell_invocation() {
  local output
  output="$(rg -nH "$CI_POLICY_SHELL_SYSTEM_CMD_PATTERN" "$@" || true)"

  if [[ -n "$output" ]]; then
    fail "shell invocation via System.cmd/3 is not allowed in runtime code"
    emit_matches "$output"
  fi
}

targets=("$@")

if [[ "${#targets[@]}" -eq 0 ]]; then
  while IFS= read -r path; do
    targets+=("$path")
  done < <(find lib -type f -name '*.ex' | sort)
fi

check_dynamic_eval "${targets[@]}"
check_shell_invocation "${targets[@]}"

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

echo "PASS: security gate passed."
