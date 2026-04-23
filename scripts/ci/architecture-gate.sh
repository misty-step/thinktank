#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/scripts/ci/gate-policy.sh"

search_repo() {
  local pattern="$1"
  local root="$2"
  shift 2

  if command -v rg >/dev/null 2>&1; then
    local args=()

    for excluded in "$@"; do
      args+=(--glob "!${excluded}")
    done

    rg -n "$pattern" "$root" "${args[@]}" || true
  else
    local output
    output="$(grep -RInE "$pattern" "$root" || true)"

    for excluded in "$@"; do
      output="$(printf '%s\n' "$output" | grep -vF "${excluded}:" || true)"
    done

    printf '%s\n' "$output" | sed '/^$/d'
  fi
}

line_count() {
  wc -l <"$1" | tr -d ' '
}

check_max_lines() {
  local path="$1"
  local limit="$2"
  local count

  count="$(line_count "$path")"

  if [[ "$count" -gt "$limit" ]]; then
    echo "FAIL: ${path} exceeds ${limit} LOC (${count})" >&2
    exit 1
  fi
}

check_artifact_layout_registry() {
  mix run --no-start -e '
case Thinktank.ArtifactLayout.validate_path_contract() do
  :ok ->
    :ok

  {:error, errors} ->
    IO.puts(:stderr, "FAIL: artifact layout registry is invalid")

    Enum.each(errors, fn {kind, paths} ->
      Enum.each(paths, &IO.puts(:stderr, "      #{kind}: #{&1}"))
    end)

    System.halt(1)
end
'
}

echo "architecture-gate: checking compile-connected cycles"
mix xref graph --format cycles --label compile-connected --fail-above 0 >/dev/null

echo "architecture-gate: checking compile-connected dependency count"
stats="$(mix xref graph --format stats --label compile-connected)"
compile_edges="$(printf '%s\n' "$stats" | awk '/^Compile dependencies:/ {print $3}')"

if [[ "${compile_edges:-}" != "0" ]]; then
  echo "FAIL: expected zero compile-connected dependencies, found ${compile_edges:-unknown}" >&2
  printf '%s\n' "$stats" >&2
  exit 1
fi

echo "architecture-gate: checking IO boundary"
io_puts_matches="$(search_repo 'IO\.puts\(' lib lib/thinktank/cli.ex)"
if [[ -n "$io_puts_matches" ]]; then
  echo "FAIL: IO.puts is only allowed in lib/thinktank/cli.ex" >&2
  printf '%s\n' "$io_puts_matches" >&2
  exit 1
fi

echo "architecture-gate: checking subprocess boundary"
system_cmd_matches="$(
  search_repo "$CI_POLICY_SYSTEM_CMD_PATTERN" lib \
    "${CI_POLICY_SYSTEM_CMD_BOUNDARIES[@]}"
)"
if [[ -n "$system_cmd_matches" ]]; then
  echo "FAIL: System.cmd is only allowed in executor and git-context boundaries" >&2
  printf '%s\n' "$system_cmd_matches" >&2
  exit 1
fi

echo "architecture-gate: checking cwd mutation boundary"
file_cd_matches="$(search_repo 'File\.cd!\(' lib)"
if [[ -n "$file_cd_matches" ]]; then
  echo "FAIL: library code must not mutate cwd with File.cd!" >&2
  printf '%s\n' "$file_cd_matches" >&2
  exit 1
fi

echo "architecture-gate: checking artifact layout registry"
check_artifact_layout_registry

echo "architecture-gate: checking module line budgets"
check_max_lines lib/thinktank/cli.ex 400
check_max_lines lib/thinktank/engine.ex 400
check_max_lines lib/thinktank/executor/agentic.ex 900
check_max_lines lib/thinktank/run_store.ex 700

echo "PASS: architecture gate passed."
