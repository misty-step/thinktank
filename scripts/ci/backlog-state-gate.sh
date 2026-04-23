#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/scripts/ci/gate-policy.sh"

failures=0

status_for_file() {
  awk -F': ' '/^Status:/ {print $2; exit}' "$1"
}

repo_anchors_for_file() {
  awk '
    /^## Repo Anchors[[:space:]]*$/ {
      in_section = 1
      next
    }

    /^## / {
      in_section = 0
    }

    in_section {
      print
    }
  ' "$1" | sed -nE 's/^[[:space:]]*-[[:space:]]*`([^`]+)`.*/\1/p'
}

check_repo_anchors() {
  local file="$1"
  local anchor
  local anchor_count=0

  while IFS= read -r anchor; do
    [[ -z "$anchor" ]] && continue

    anchor_count=$((anchor_count + 1))

    if [[ ! -e "$anchor" ]]; then
      echo "FAIL: repo anchor does not exist in $file: $anchor" >&2
      failures=1
    fi
  done < <(repo_anchors_for_file "$file")

  if [[ "$anchor_count" -eq 0 ]]; then
    echo "FAIL: active backlog item must list at least one live repo anchor: $file" >&2
    failures=1
  fi
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
      elif ! ci_policy_is_active_backlog_status "$status"; then
        echo "FAIL: $file has unsupported active Status '$status'" >&2
        failures=1
      else
        check_repo_anchors "$file"
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
