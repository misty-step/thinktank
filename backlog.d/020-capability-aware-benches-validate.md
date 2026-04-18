# Capability-Aware Benches Validate

Priority: medium
Status: ready
Estimate: M

## Goal

`thinktank benches validate` catches provider-capability mismatches — e.g. a reviewer model that doesn't advertise `tools` in OpenRouter's `supported_parameters` when the bench declares `@agent_tools` — before any run is launched, instead of surfacing them as silent run-time degrades.

## Non-Goals

- Caching OpenRouter catalog state across invocations (keep the probe inline; catalog drift is a feature, not a bug)
- Expanding `validate` into a dry-run of the actual agent prompts
- Adding a new provider abstraction layer — probe paths stay provider-specific
- Blocking `thinktank benches validate --dry-run` when the network is unreachable; treat unreachable as skip + warn, not fail

## Constraints / Invariants

- Validation must be fast (<5s for the full built-in bench catalog) when the provider catalog responds normally
- No credential is exfiltrated beyond the existing `THINKTANK_OPENROUTER_API_KEY` / `OPENROUTER_API_KEY` env contract
- A capability miss must produce a typed, user-actionable error — naming the bench, the agent, the declared tools, and the missing provider capability — not a raw HTTP body
- When the API key is absent, validation falls back to structural-only behavior with a single explanatory warning; it never fails closed on missing credentials
- Adding this check does not change the shape of the existing `benches validate --json` success payload; capability findings live under a new `warnings` / `errors` field on top of the existing `{status, bench_count}` envelope (schema extension, not breakage)

## Repo Anchors

- `lib/thinktank/cli/parser.ex` — `benches validate` command surface
- `lib/thinktank/engine/preparation.ex` — current bench/agent/synth resolution path; the natural home for a new capability probe
- `lib/thinktank/builtin.ex` — bench declared `@agent_tools` and `@summary_tools`
- `test/thinktank/integration/review_bench_capability_test.exs` — existing live probe against OpenRouter; can be reused as the capability predicate
- Providers config under `config["providers"]` — adapter selection lives here

## Evidence

Backlog 019 documents the exact failure mode that this would have caught at validate-time: a `*-multi-agent` xAI variant that lacks `tools` in `supported_parameters`, shipping in `review/default` and 404'ing on every guard invocation. Today's validate path (`--dry-run`) is structural-only — it resolves bench shape without probing providers — and surfaces the mismatch only at run-time. Fix 019 removed the specific offending model; 020 is the structural prevention so the next incompatible swap fails at validate time, not mid-review.

## Oracle

- [ ] `thinktank benches validate` probes each agent's configured model for the bench's declared tool set against the provider catalog, and fails with a typed error when a mismatch is detected
- [ ] When `OPENROUTER_API_KEY` is absent the command degrades to structural-only validation and emits a single visible warning explaining the capability gap
- [ ] `mix test --include integration` covers: (a) a bench with a known-incompatible model fails validate with a typed error; (b) absent-credential mode still returns a structural pass
- [ ] End-to-end wall-clock for the built-in catalog stays under 5 s on a normal OpenRouter response (measured in an integration test, not just asserted)
- [ ] The `--json` payload gains the capability findings in an additive, documented way

## Notes

Prior art already lives in-repo at `test/thinktank/integration/review_bench_capability_test.exs` (added in backlog 019): it probes `GET /api/v1/models/<slug>/endpoints` and asserts `tools` in each endpoint's `supported_parameters`. Lift that predicate into a first-class capability check invoked by `benches validate` (and optionally by `engine/preparation.ex` behind a flag) instead of re-implementing it per caller.

Parked from the 019 notes: this item carries the "capability-aware bench validation" follow-up that the fix deferred as out-of-scope.
