---
name: demo
description: |
  Produce evidence for ThinkTank CLI changes: bench listings, dry-run launches,
  artifact walkthroughs, and validation transcripts. Trigger: /demo.
argument-hint: "[feature|PR-number] [--format txt|gif]"
---

# /demo

ThinkTank demos should show the CLI and artifact contract in action. Useful
evidence includes `./thinktank benches list`, bench inspection, dry-run
research/review launches, JSON output, artifact trees, manifests, and relevant
validation transcripts.

Gradient-managed harness changes may also need `gradient validate` output, but
that is supporting evidence. It does not demonstrate ThinkTank behavior by
itself.

## Source Of Truth

Read `.claude/skills/demo/SKILL.md` for the repo-authored capture workflow,
safe demo commands, and cost boundaries for live model calls.
