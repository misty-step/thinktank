# Add Structured Research Findings Contract

Priority: high
Status: done
Estimate: M

## Goal
Research benches become more useful to both humans and downstream agents because ThinkTank writes a canonical structured findings artifact alongside the prose synthesis, so claims, evidence, open questions, and confidence can be consumed without parsing markdown.

## Non-Goals
- Replacing `synthesis.md` with JSON-only output
- Adding a scoring framework for research quality in the same change
- Expanding review benches in the same item
- Recovering structure from free-form prose with regexes

## Constraints / Invariants
- Raw agent outputs remain durable source artifacts; the structured findings file is a derived contract, not a replacement for them
- Structured output must come from an explicit schema-driven synthesis step, not post-hoc markdown parsing
- The schema should stay small and stable: thesis, findings, evidence, open questions, and confidence are enough to start
- Partial or failed synthesis must surface a typed reason rather than a missing file
- `--json` stdout remains additive and machine-safe

## Repo Anchors
- `lib/thinktank/prompts/synthesis.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/artifact_layout.ex`
- `lib/thinktank/builtin.ex`
- `README.md`

## Oracle
- [x] `research/default` writes a canonical structured findings artifact in addition to `synthesis.md`
- [x] The structured artifact contains at least: `thesis`, `findings[]`, `evidence[]`, `open_questions[]`, and `confidence`
- [x] A synthesis failure or partial run produces an explicit typed status for the structured artifact instead of silently omitting it
- [x] `README.md` documents the structured research artifact and its role relative to raw outputs
- [x] Automated coverage proves successful structured synthesis, invalid-structure fallback, and partial-run behavior

## What Was Built
- Research synthesis is now schema-first: `research-synth` returns structured JSON, `research/findings.json` is the canonical machine contract, and `synthesis.md` is rendered from validated findings.
- Invalid JSON, invalid schema, synthesizer failures, and partial no-synthesis runs all surface typed `research_findings` statuses in the result envelope.
- Result envelopes read findings only from manifest-recorded artifacts so reused output directories cannot leak stale files.

## Notes
ThinkTank already records durable research artifacts, but today the synthesized result is primarily markdown. That is readable, but it limits reuse by downstream tools and makes “council of intelligence” style consumers depend on prose interpretation.

This item improves the research flow without violating the thin-launcher boundary: ThinkTank still launches agents and records artifacts, while Pi agents produce the structured synthesis contract.
