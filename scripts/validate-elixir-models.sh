#!/bin/bash
set -euo pipefail

# validate-elixir-models.sh — Validate Elixir model IDs against OpenRouter API
#
# Extracts hardcoded OpenRouter model ID strings from Elixir source files
# and validates each one exists in the live OpenRouter models API.
#
# Run: scripts/validate-elixir-models.sh
# Exit: 0 if all valid, 1 if any stale/unknown model IDs found

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Extract model ID strings from Elixir source files
PROVIDERS="anthropic\|openai\|google\|deepseek\|meta-llama\|mistralai\|qwen\|moonshotai\|nvidia\|bytedance-seed\|inception\|x-ai"
ELIXIR_MODELS=$(grep -rho "\"\\(${PROVIDERS}\\)/[a-z0-9._-]*\"" \
  "$REPO_ROOT/lib/" \
  2>/dev/null \
  | tr -d '"' \
  | sort -u || true)

if [ -z "$ELIXIR_MODELS" ]; then
  echo "No model IDs found in Elixir source files."
  exit 0
fi

# Validate against live OpenRouter API (source of truth)
VALID_MODELS=""

if command -v curl &>/dev/null; then
  VALID_MODELS=$(curl -sf --max-time 10 https://openrouter.ai/api/v1/models 2>/dev/null \
    | python3 -c "import json,sys; [print(m['id']) for m in json.load(sys.stdin).get('data',[])]" 2>/dev/null \
    || true)
fi

if [ -z "$VALID_MODELS" ]; then
  echo "Warning: OpenRouter API unreachable — skipping validation"
  exit 0
fi

STALE=0
echo "Validating Elixir model IDs against OpenRouter API..."
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
  echo "FAIL: $STALE model ID(s) not found in OpenRouter API"
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
