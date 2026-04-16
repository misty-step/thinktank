#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

failures=0

status_for_file() {
  awk -F': ' '/^Status:/ {print $2; exit}' "$1"
}

check_file() {
  local file="$1"
  local status

  [[ -f "$file" ]] || return 0

  case "$file" in
    backlog.d/README.md)
      return 0
      ;;
  esac

  status="$(status_for_file "$file")"

  if [[ -z "$status" ]]; then
    echo "FAIL: missing Status: field in $file" >&2
    failures=1
    return 0
  fi

  case "$file" in
    backlog.d/done/*.md)
      if [[ "$status" != "done" ]]; then
        echo "FAIL: $file lives under backlog.d/done/ but Status is '$status'" >&2
        failures=1
      fi
      ;;
    backlog.d/*.md)
      if [[ "$status" == "done" ]]; then
        echo "FAIL: $file is a top-level backlog item marked done." >&2
        echo "      Move merged items to backlog.d/done/ during the squash/merge step." >&2
        failures=1
      fi
      ;;
  esac
}

if [[ "$#" -gt 0 ]]; then
  for file in "$@"; do
    check_file "$file"
  done
else
  while IFS= read -r file; do
    check_file "$file"
  done < <(find backlog.d -type f -name '*.md' | sort)
fi

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

echo "PASS: backlog state gate passed."
