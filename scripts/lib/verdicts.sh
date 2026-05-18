#!/usr/bin/env bash
set -euo pipefail

gradient_verdict_validate_json() {
  go run ./cmd/gradient validate >/dev/null
}

gradient_verdict_sha() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}
