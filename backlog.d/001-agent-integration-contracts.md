# Agent Integration Contracts

Priority: high
Status: in-progress
Estimate: M

## Goal
Agents can discover available benches/agents, parse run results, and distinguish error categories — all programmatically, without filesystem access or source code reading.

## Non-Goals
- HTTP API (CLI is the interface)
- Deterministic/resumable runs (separate concern)
- Changing internal architecture (just expose what exists)

## Oracle
- [ ] `thinktank benches show <name> --full --json` returns complete agent specs: model, tools, system prompt, thinking level, timeout
- [ ] Result envelope (`--json` output) includes inline synthesis summary text and per-artifact `content_type` field
- [ ] All error paths from executor → engine → CLI use a consistent `{:error, %{code: atom, message: binary, details: map}}` shape
- [ ] `thinktank benches list --json` includes agent count and kind for each bench
- [ ] An agent can select a bench, run it, and parse the result without touching the filesystem — verified by a test that exercises the full path

## Notes
Building blocks exist: RunContract, BenchSpec, AgentSpec are well-typed structs. The work is wiring them into the CLI output and unifying error shapes. Archaeologist found error asymmetry across executor (structured map), engine (raw atoms), and CLI (ad-hoc format_reason/1). Strategist confirmed result envelope returns file pointers but no summaries. Velocity confirmed the specs exist but aren't exposed.
