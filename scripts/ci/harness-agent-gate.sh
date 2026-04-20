#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d .claude/agents ]; then
  echo "PASS: harness agent gate skipped (.claude/agents absent)."
  exit 0
fi

failures=0

fail_matches() {
  local message="$1"
  local matches="$2"

  echo "FAIL: ${message}" >&2
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "      ${line}" >&2
  done <<<"$matches"
  failures=1
}

frontmatter_matches="$(
  rg -nH '^(model|default_model|preferred_model|model_name|reasoning_effort|reasoning_level):' \
    .claude/agents/*.md || true
)"

if [ -n "$frontmatter_matches" ]; then
  fail_matches ".claude/agents must not declare model or reasoning selection fields" \
    "$frontmatter_matches"
fi

provider_slug_matches="$(
  rg -nH '\b(openai|anthropic|google|x-ai|mistralai|minimax|moonshotai|z-ai)/[A-Za-z0-9._-]+\b' \
    .claude/agents/*.md || true
)"

if [ -n "$provider_slug_matches" ]; then
  fail_matches ".claude/agents must not hardcode provider/model slugs" \
    "$provider_slug_matches"
fi

named_model_matches="$(
  rg -nH '\b(gpt-[0-9][A-Za-z0-9._-]*|claude-(opus|sonnet|haiku)[A-Za-z0-9._-]*|gemini-[0-9][A-Za-z0-9._-]*|grok-[0-9][A-Za-z0-9._-]*|glm-[0-9][A-Za-z0-9._-]*|kimi-[A-Za-z0-9._-]+)\b' \
    .claude/agents/*.md || true
)"

if [ -n "$named_model_matches" ]; then
  fail_matches ".claude/agents must not mention concrete model families by name" \
    "$named_model_matches"
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "PASS: harness agent gate passed."
