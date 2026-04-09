#!/usr/bin/env python3
"""Validate hardcoded Elixir model IDs against the live OpenRouter catalog."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROVIDERS = (
    "anthropic",
    "bytedance-seed",
    "deepseek",
    "google",
    "inception",
    "meta-llama",
    "minimax",
    "mistralai",
    "moonshotai",
    "nvidia",
    "openai",
    "qwen",
    "x-ai",
    "xiaomi",
    "z-ai",
)

MODEL_RE = re.compile(
    r'"(?P<id>(?:' + "|".join(re.escape(provider) for provider in PROVIDERS) + r')/[A-Za-z0-9._-]+)"'
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo-root",
        default=".",
        help="repository root to scan (default: current directory)",
    )
    parser.add_argument(
        "--fail-on-unreachable",
        action="store_true",
        help="treat OpenRouter API reachability failures as fatal",
    )
    return parser.parse_args()


def scan_model_ids(repo_root: Path) -> tuple[list[str], dict[str, list[str]]]:
    model_ids: set[str] = set()
    locations: dict[str, list[str]] = {}

    for path in sorted((repo_root / "lib").rglob("*.ex")):
        for line_no, line in enumerate(path.read_text().splitlines(), start=1):
            for match in MODEL_RE.finditer(line):
                model_id = match.group("id")
                model_ids.add(model_id)
                locations.setdefault(model_id, []).append(f"{path}:{line_no}:{line.strip()}")

    return sorted(model_ids), locations


def fetch_valid_models() -> set[str]:
    request = urllib.request.Request(
        "https://openrouter.ai/api/v1/models",
        headers={"User-Agent": "thinktank-model-validator/1"},
    )

    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)

    return {entry["id"] for entry in payload.get("data", []) if isinstance(entry, dict) and "id" in entry}


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    model_ids, locations = scan_model_ids(repo_root)

    if not model_ids:
        print("No model IDs found in Elixir source files.")
        return 0

    try:
        valid_models = fetch_valid_models()
    except (OSError, TimeoutError, urllib.error.URLError, json.JSONDecodeError) as error:
        message = f"OpenRouter API unreachable: {error}"
        if args.fail_on_unreachable:
            print(f"FAIL: {message}")
            return 1

        print(f"Warning: {message} — skipping validation")
        return 0

    stale = 0
    print("Validating Elixir model IDs against OpenRouter API...")
    print()

    for model_id in model_ids:
        if model_id in valid_models:
            print(f"  ok  {model_id}")
            continue

        stale += 1
        print(f"  STALE  {model_id}")
        for location in locations.get(model_id, []):
            print(f"         {location}")

    print()

    if stale:
        print(f"FAIL: {stale} model ID(s) not found in OpenRouter API")
        return 1

    print("PASS: All Elixir model IDs are valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
