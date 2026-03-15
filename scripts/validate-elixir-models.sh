#!/bin/bash
set -euo pipefail

# validate-elixir-models.sh — Ensure Elixir model IDs match the Go registry
#
# Extracts hardcoded OpenRouter model ID strings from Elixir source files
# and validates each one exists in internal/models/models.go.
#
# Run: scripts/validate-elixir-models.sh
# Exit: 0 if all valid, 1 if any stale/unknown model IDs found

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="$REPO_ROOT/internal/models/models.go"

if [ ! -f "$REGISTRY" ]; then
  echo "Warning: Go model registry not found at $REGISTRY — skipping validation"
  exit 0
fi

# Extract all APIModelID values from the Go registry
# Format: APIModelID:      "provider/model-name"
VALID_MODELS=$(grep 'APIModelID:' "$REGISTRY" \
  | sed 's/.*"\(.*\)".*/\1/' \
  | sort -u)

# Extract model ID strings from Elixir source files
# Uses known LLM provider prefixes to identify model IDs
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

STALE=0
echo "Validating Elixir model IDs against Go registry..."
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
  echo "FAIL: $STALE model ID(s) not found in Go registry ($REGISTRY)"
  echo ""
  echo "To fix:"
  echo "  1. Check https://openrouter.ai/models for current model IDs"
  echo "  2. Update internal/models/models.go if the model is valid but missing"
  echo "  3. Update the Elixir source to use a current model ID"
  exit 1
else
  echo "PASS: All Elixir model IDs are valid."
  exit 0
fi
