---
name: thinktank-demo
description: |
  Generate demo artifacts for thinktank CLI. Terminal captures of bench
  launches, artifact walkthroughs, dry-run output.
  Use when: "make a demo", "demo this", "PR evidence", "record walkthrough".
  Trigger: /demo.
disable-model-invocation: true
argument-hint: "[feature|PR-number] [--format txt|gif] [upload]"
---

# /demo

Capture thinktank CLI in action. Terminal output captures by default;
GIF recordings for README or launch artifacts.

## Capture Methods

| Feature | Method | Tool | Output |
|---------|--------|------|--------|
| Bench listing | Output capture | script/redirect | `.txt` |
| Bench inspection | Output capture | script/redirect | `.txt` |
| Dry-run | Output capture | script/redirect | `.txt` |
| Full research run | Output capture + artifact tree | script/redirect | `.txt` |
| Full review run | Output capture + artifact tree | script/redirect | `.txt` |
| Any CLI flow | Terminal GIF | asciinema + agg | `.gif` |

## Workflow: Planner -> Implementer -> Critic

### 1. Plan

Identify what to demo based on the PR or feature:

- What changed? (read the diff or PR description)
- Which commands show the change? (before -> after)
- What artifacts prove it worked?

Build a shot list:

| # | Command | Shows | Before State | After State |
|---|---------|-------|-------------|------------|

### 2. Capture

**Output capture (default):**

```bash
mkdir -p /tmp/demo-thinktank
mix escript.build

# Capture command output with exit code
{
  echo "$ ./thinktank [command] [args]"
  ./thinktank [command] [args] 2>&1
  echo ""
  echo "Exit code: $?"
} > /tmp/demo-thinktank/01-feature-name.txt
```

**Artifact tree capture:**

```bash
OUTPUT=$(ls -td /tmp/thinktank-* | head -1)
{
  echo "Artifact directory: $OUTPUT"
  echo ""
  find "$OUTPUT" -type f | sort
  echo ""
  echo "=== contract.json ==="
  jq . "$OUTPUT/contract.json"
  echo ""
  echo "=== manifest.json ==="
  jq . "$OUTPUT/manifest.json"
} > /tmp/demo-thinktank/02-artifacts.txt
```

**Terminal GIF (for README or launch):**

```bash
# Record terminal session
asciinema rec /tmp/demo-thinktank/session.cast \
  --command "./thinktank benches list && ./thinktank research 'analyze' --dry-run"

# Convert to GIF
agg /tmp/demo-thinktank/session.cast /tmp/demo-thinktank/demo.gif \
  --cols 100 --rows 30 --font-size 14
```

If asciinema/agg unavailable, use script + manual annotation:

```bash
script -q /tmp/demo-thinktank/session.txt ./demo-script.sh
```

Rules:
- Every "after" has a paired "before" at the same viewport/command
- Dry-run captures are free — prefer them for non-critical demos
- Full run captures should show the artifact tree, not just stdout
- Target: GIFs < 5MB, text captures < 50KB

### 3. Critique

Launch a **fresh subagent** (no context from the implementer) to review:

- Does each capture show a meaningful delta (not just default state)?
- Are before/after pairs present for claimed changes?
- Is the text readable and the flow logical?
- Do artifact trees match what the code should produce?
- Are GIFs under 5MB with > 10 frames?

### 4. Upload (if requested)

```bash
# Bundle evidence
PR_NUM=123
cd /tmp/demo-thinktank
tar czf evidence.tar.gz *.txt *.gif 2>/dev/null

# Create draft release and upload
gh release create qa-evidence-pr-${PR_NUM} \
  --draft \
  --title "QA Evidence: PR #${PR_NUM}" \
  --notes "Demo artifacts for PR #${PR_NUM}" \
  /tmp/demo-thinktank/*.txt /tmp/demo-thinktank/*.gif 2>/dev/null

# Comment on PR
gh pr comment ${PR_NUM} --body "Demo evidence uploaded to draft release qa-evidence-pr-${PR_NUM}"
```

## Demo-Worthy Features

| # | Feature | Safe? | Command |
|---|---------|-------|---------|
| 1 | Bench listing | Yes | `./thinktank benches list` |
| 2 | Bench inspection | Yes | `./thinktank benches show research/default --full` |
| 3 | Bench validation | Yes | `./thinktank benches validate` |
| 4 | Dry-run research | Yes | `./thinktank research "query" --dry-run` |
| 5 | Dry-run review | Yes | `./thinktank review --dry-run` |
| 6 | Full research run | API call | `./thinktank research "query" --paths lib/` |
| 7 | Full review run | API call | `./thinktank review --base main --head HEAD` |
| 8 | JSON output | Yes | `./thinktank benches list --json` |
| 9 | Error handling | Yes | `./thinktank benches show nonexistent` |

Items marked "Yes" are safe (no API calls, no cost). Use these for routine demos.

## Gotchas

- **Rebuild before capture.** `mix escript.build` — stale binary ruins demos.
- **Default-state evidence proves nothing.** Show the delta: before/after, or the specific feature in action.
- **Self-grading is worthless.** The critic subagent must inspect artifacts cold (no shared context with the implementer).
- **Full runs cost money.** Only capture full research/review runs when the demo specifically needs live agent output.
- **Artifact paths have timestamps.** Use `ls -td /tmp/thinktank-* | head -1`, not hardcoded paths.
- **GIFs from asciinema need agg.** If agg isn't installed, fall back to text captures. Don't produce broken GIFs.
- **Never commit binary artifacts to the repo.** Upload to draft releases or keep in /tmp.
