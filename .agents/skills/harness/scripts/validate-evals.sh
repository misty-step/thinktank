#!/usr/bin/env bash
set -euo pipefail

root="${1:-skills}"

if [ ! -d "$root" ]; then
  echo "FAIL: $root not found" >&2
  exit 1
fi

checked=0
failed=0

while IFS= read -r evals_dir; do
  checked=$((checked + 1))
  skill="$(basename "$(dirname "$evals_dir")")"
  if [ ! -f "$evals_dir/README.md" ]; then
    echo "FAIL: $root/$skill/evals: missing README.md" >&2
    failed=1
  fi
  if ! find "$evals_dir/cases" -type f -maxdepth 1 2>/dev/null | grep -q .; then
    echo "FAIL: $root/$skill/evals: missing at least one case file" >&2
    failed=1
  fi
  if ! find "$evals_dir/graders" -type f -maxdepth 1 2>/dev/null | grep -q .; then
    echo "FAIL: $root/$skill/evals: missing at least one grader" >&2
    failed=1
  fi
done < <(find "$root" -path '*/evals' -type d | sort)

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "OK: $checked skill eval suite(s) valid"
