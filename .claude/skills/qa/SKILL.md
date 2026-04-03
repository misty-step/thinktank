---
name: thinktank-qa
description: |
  QA for thinktank CLI. Run benches, verify artifacts, check exit codes.
  Use when: "run QA", "test this", "verify the feature", "QA this PR".
  Trigger: /qa.
disable-model-invocation: true
argument-hint: "[command|bench-id|PR-number]"
---

# /qa

Verify thinktank CLI behavior: commands execute correctly, artifacts are
well-formed, exit codes match expectations.

## Prerequisites

- Escript is built: `mix escript.build`
- Working directory has a git repo (most commands need one)

## Build

```bash
mix escript.build
```

Rebuild after any code change. If the build fails, that's a P0 — stop QA.

## Critical Paths

| # | Command | What to Check |
|---|---------|---------------|
| 1 | `./thinktank --help` | Exit 0, usage text includes `research`, `review`, `benches` |
| 2 | `./thinktank --version` | Exit 0, prints `thinktank X.Y.Z` |
| 3 | `./thinktank benches list` | Exit 0, lists `research/default` and `review/default` |
| 4 | `./thinktank benches show research/default` | Exit 0, valid JSON with agents array |
| 5 | `./thinktank benches show research/default --full` | Exit 0, JSON includes full agent specs |
| 6 | `./thinktank benches validate` | Exit 0, no validation errors |
| 7 | `./thinktank research "test" --dry-run` | Exit 0, prints resolved bench without launching agents |
| 8 | `./thinktank review --dry-run` | Exit 0, prints resolved review bench |
| 9 | `./thinktank benches show nonexistent` | Exit 7, prints error message to stderr |
| 10 | `./thinktank research "test" --dry-run --json` | Exit 0, stdout is valid JSON |

## Interactive Flows (if PR touches these)

| Flow | Steps |
|------|-------|
| Research run | `research "analyze logging" --paths ./lib --dry-run` (or live) — verify agents/ dir, task.md, contract.json, manifest.json |
| Review run | `review --base origin/main --head HEAD` — verify review/, agents/, plan artifacts |
| Review eval | `review eval <prior-run-dir>` — verify replay produces fresh artifacts |
| Repo config | Create `.thinktank/config.yml`, run with `--trust-repo-config` — verify custom bench loads |
| JSON output | Add `--json` to any command — verify valid JSON envelope on stdout |

**Full runs call live APIs.** Only run these when the PR touches engine, executor,
or prompt code. Use `--dry-run` for everything else.

## Artifact Validation

After any full run, verify the output directory:

```bash
OUTPUT=$(ls -td /tmp/thinktank-* | head -1)

# Required artifacts
test -f "$OUTPUT/contract.json" && echo "contract.json: ok"
test -f "$OUTPUT/task.md" && echo "task.md: ok"
test -f "$OUTPUT/manifest.json" && echo "manifest.json: ok"

# contract.json is valid JSON
jq . "$OUTPUT/contract.json" > /dev/null && echo "contract.json: valid JSON"

# manifest.json has expected fields
jq '.bench_id, .status, .artifacts' "$OUTPUT/manifest.json"

# Agent outputs exist
ls "$OUTPUT/agents/"*.md 2>/dev/null && echo "agent outputs: ok"
```

## Evidence

Evidence goes to `/tmp/qa-thinktank/`.

```bash
mkdir -p /tmp/qa-thinktank
```

Capture strategy (CLI tool — no browser):

| What | How | File |
|------|-----|------|
| Command output | Redirect stdout+stderr | `cmd-{name}.txt` |
| Exit codes | `echo $?` after each command | Inline in output files |
| Artifact structure | `find $OUTPUT -type f` | `artifacts.txt` |
| JSON validity | `jq . <file>` | Pass/fail in output |
| Error cases | Run invalid commands | `errors.txt` |

## Gotchas

- **Rebuild before QA.** Stale escript is the #1 false failure — always `mix escript.build` first.
- **Full runs cost money.** Only run research/review without `--dry-run` when the PR touches agent dispatch, prompts, or synthesis.
- **Exit code 7 vs 1.** Input errors (bad args, unknown bench) exit 7. Runtime errors exit 1. Verify the distinction.
- **JSON mode changes output shape.** `--json` wraps output in an envelope — test both human and JSON output if the PR touches formatting.
- **Repo config is opt-in.** `.thinktank/config.yml` only loads with `--trust-repo-config`. Test both trusted and untrusted paths.
- **Review planner is non-deterministic.** The marshal agent may select different reviewers each run. Validate structure, not exact agent list.
- **Artifact paths contain timestamps.** Don't hardcode paths — use `ls -td /tmp/thinktank-* | head -1` to find the latest run.
