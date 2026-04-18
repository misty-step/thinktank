# Reduce Review Control Plane To Structured Contracts

Priority: high
Status: ready
Estimate: M

## Goal
Review benches stay thin because planning and orientation depend on strict machine-readable contracts instead of prose recovery, regex salvage, and artifact sprawl.

## Non-Goals
- Deleting the planner or reviewer roster
- Replacing agent reasoning with harness heuristics
- Blocking human-readable markdown artifacts when they are cheap derivatives

## Constraints / Invariants
- Planner output is accepted only as strict JSON matching the review plan schema
- Invalid planner output yields an explicit recorded failure plus deterministic fallback, not brace or fenced-code recovery
- Canonical review control artifacts are typed JSON; markdown summaries are optional derivatives and never gating
- Reviewers still inspect the repo themselves; orientation artifacts remain hints

## Repo Anchors
- `lib/thinktank/review/planner.ex`
- `lib/thinktank/engine/preparation.ex`
- `lib/thinktank/prompts/review.ex`
- `lib/thinktank/prompts/synthesis.ex`
- `README.md`

## Oracle
- [ ] `Thinktank.Review.Planner` removes regex/brace-based candidate extraction and accepts only schema-valid JSON plans
- [ ] Invalid planner output produces a deterministic fallback plan plus an explicit artifact or trace event explaining why fallback happened
- [ ] Review execution no longer depends on both JSON and Markdown context/plan artifacts being present
- [ ] README and tests describe review context/plan artifacts as orientation-only and document the canonical structured contract

## Notes
The project doctrine says ThinkTank should not parse agent prose with regexes. This item closes the gap by making the review control plane depend on explicit contracts rather than model formatting.
