#!/bin/bash
set -euo pipefail

# validate-elixir-models.sh — Validate Elixir model IDs against OpenRouter API
#
# Extracts hardcoded OpenRouter model ID strings from Elixir source files
# and validates each one exists in the live OpenRouter models API.
#
# Falls back to the Go registry if the API is unreachable.
#
# Run: scripts/validate-elixir-models.sh
# Exit: 0 if all valid, 1 if any stale/unknown model IDs found

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="$REPO_ROOT/internal/models/models.go"

# Extract model ID strings from Elixir source files
PROVIDERS="anthropic\|openai\|google\|deepseek\|meta-llama\|mistralai\|qwen\|moonshotai"
ELIXIR_MODELS=$(grep -rho "\"\\(${PROVIDERS}\\)/[a-z0-9._-]*\"" \
  "$REPO_ROOT/lib/" \
  2>/dev/null \
  | tr -d '"' \
  | sort -u || true)

if [ -z "$ELIXIR_MODELS" ]; then
  echo "No model IDs found in Elixir source files."
  exit 0
fi

# Try live OpenRouter API first (source of truth)
VALID_MODELS=""
API_SOURCE="OpenRouter API"

if command -v curl &>/dev/null; then
  API_MODELS=$(curl -sf --max-time 10 https://openrouter.ai/api/v1/models 2>/dev/null \
    | python3 -c "import json,sys; [print(m['id']) for m in json.load(sys.stdin).get('data',[])]" 2>/dev/null \
    || true)

  if [ -n "$API_MODELS" ]; then
    VALID_MODELS="$API_MODELS"
  fi
fi

# Fall back to Go registry if API unreachable
if [ -z "$VALID_MODELS" ]; then
  if [ -f "$REGISTRY" ]; then
    VALID_MODELS=$(grep 'APIModelID:' "$REGISTRY" \
      | sed 's/.*"\(.*\)".*/\1/' \
      | sort -u)
    API_SOURCE="Go registry (API unreachable)"
  else
    echo "Warning: Neither OpenRouter API nor Go registry available — skipping validation"
    exit 0
  fi
fi

STALE=0
echo "Validating Elixir model IDs against $API_SOURCE..."
echo ""

while IFS= read -r model; do
  if echo "$VALID_MODELS" | grep -qF "$model"; then
    echo "  ok  $model"
  else
    echo "  STALE  $model"
    grep -rn "\"$model\"" "$REPO_ROOT/lib/" 2>/dev/null | sed 's/^/         /'
    STALE=$((STALE + 1))
  fi
done <<< "$ELIXIR_MODELS"

echo ""

if [ "$STALE" -gt 0 ]; then
  echo "FAIL: $STALE model ID(s) not found in $API_SOURCE"
  echo ""
  echo "To fix:"
  echo "  1. Run: curl -s https://openrouter.ai/api/v1/models | python3 -c \"import json,sys; [print(m['id']) for m in json.load(sys.stdin)['data']]\""
  echo "  2. Find the correct current model ID"
  echo "  3. Update the Elixir source"
  exit 1
else
  echo "PASS: All Elixir model IDs are valid."
  exit 0
fi
