# Fix Default Review Bench Guard Agent Incompatibility

Priority: high
Status: done
Estimate: S

## What Was Built
- Routed the `guard` reviewer in `review/default` to `x-ai/grok-4.20` (same reasoning tier, same pricing, tool-capable on OpenRouter) in `lib/thinktank/builtin.ex`, replacing the incompatible `x-ai/grok-4.20-multi-agent` variant.
- Dropped the now-unused `x-ai/grok-4.20-multi-agent` entry from `lib/thinktank/pricing.ex`; every builtin model still has a price table row so `PricingTest` stays green.
- Added a short inline capability note in `lib/thinktank/builtin.ex` above the reviewer list explaining why `*-multi-agent` variants must stay out of tool-using benches.
- Added `test/thinktank/integration/review_bench_capability_test.exs` (`@moduletag :integration`) that probes each reviewer's OpenRouter endpoints for `tools` in `supported_parameters`; gated on `OPENROUTER_API_KEY`. Updated `test/test_helper.exs` to exclude `:integration` from the default run so `mix test` stays offline.

## Goal

The shipped `review/default` bench succeeds with all reviewers on every run — no silent degrade caused by a built-in agent's model being incompatible with the bench's required tool set.

## Non-Goals

- Reworking the review bench composition or roster.
- Adding new reviewer agents.
- Changing pricing or quotas.
- Expanding the broader capability-validation work (filed as 020 below).

## Constraints / Invariants

- Every agent in `review/default` must be able to call the bench's declared `@agent_tools` (`bash, read, grep, find, ls`) at the configured provider.
- Model substitutions must preserve the agent's role identity (security agent stays on a comparable security-tier reasoning model — no silent downgrade to a smaller model just to satisfy the tool requirement).
- No change to OpenRouter routing knobs or `pi`-level invocation semantics.

## Repo Anchors

- `lib/thinktank/builtin.ex:97` — guard agent currently routed to `x-ai/grok-4.20-multi-agent`
- `lib/thinktank/builtin.ex:96` — trace agent uses `x-ai/grok-4.20` (regular variant, tool-capable)
- `lib/thinktank/pricing.ex:16` — pricing entry for `x-ai/grok-4.20-multi-agent` (drop or keep depending on whether the variant remains in the catalog)

## Evidence

Reproduced 2026-04-18 against thinktank 6.3.0:

```
$ thinktank review --base main --head HEAD -o /tmp/review --json
# (run completed in degraded state: 3 of 4 reviewers ok)

$ jq -r .status /tmp/review/trace/summary.json
degraded

$ cat /tmp/review/agents/guard-*.md
Warning: Model "x-ai/grok-4.20-multi-agent" not found for provider "openrouter". Using custom model id.
404 No endpoints found that support tool use. Try disabling "bash". To learn more about provider routing, visit: https://openrouter.ai/docs/guides/routing/provider-selection

ERROR: %{category: :crash, exit_code: 1}
```

Retried 3× per default backoff; all three attempts hit the same 404. Total wasted spend: ~12s × 3 attempts on a doomed call.

OpenRouter catalog confirms the model exists but does not advertise tool support:

```
$ curl -s https://openrouter.ai/api/v1/models/x-ai/grok-4.20-multi-agent/endpoints \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  | jq '.data.endpoints[].supported_parameters'
[
  "reasoning", "include_reasoning", "max_tokens", "temperature",
  "top_p", "seed", "logprobs", "top_logprobs",
  "response_format", "structured_outputs"
]
# Note: no "tools" entry. xAI's Multi-Agent variant orchestrates its own tool
# fabric internally and does not accept a user-supplied tool schema through
# OpenRouter.
```

The non-multi-agent sibling `x-ai/grok-4.20` does support tools (verified by the trace agent succeeding against the same bench).

Impact on a real review run: a security-themed PR (Apollo webhook HMAC + rate limit hardening at `adminifi/vulcan` branch `feat/024a-webhook-hmac-rate-limit`, 12 files / +1201 LOC) ran with **no security reviewer**. The synthesizer correctly noted "trace and pulse checked runtime behavior" but never named the missing security perspective. For a marshal-tagged security review, silently producing a no-security-reviewer synthesis is a quality regression that the review-synth contract does not currently flag.

## Oracle

- [ ] `thinktank review --base main --head HEAD -o /tmp/r1` against any non-trivial diff returns `status: ok` (not `degraded`) when all configured providers are reachable.
- [ ] `lib/thinktank/builtin.ex` guard agent uses a tool-capable model on a security-tier reasoning class (e.g. `x-ai/grok-4.20`, or another model the team selects with the same capability profile).
- [ ] `mix test` covers the fix: a unit test asserts every reviewer in the `review_agents/0` roster is wired to a model whose OpenRouter endpoint advertises `tools` in `supported_parameters`. (Test may be marked `@tag :integration` and gated on `OPENROUTER_API_KEY`.)
- [ ] `priv/` or wherever model capability metadata lives gets a one-line note on why the multi-agent variant is unsuitable for tool-using benches (so the next person doesn't re-add it).

## Notes

This bug was caught by a downstream consumer (the spellbook `/code-review` skill) running thinktank as one of three review tiers on a security PR. The other two tiers (Claude internal bench, Codex CLI) caught the security findings thinktank missed because guard never ran. Without those backstops, the shipped review would have silently lacked the security perspective on a security-themed change.

For thinktank's stated trajectory — owning code review in all contexts — that silent-degrade-with-quality-gap pattern is the failure mode worth designing against. Two scoped follow-ups (file as separate items if they earn their own oracle):

- **020 — Capability-aware bench validation.** Today `thinktank benches validate` is structural-only and `--dry-run` resolves bench shape without probing providers. A capability check (probe each agent's model's `supported_parameters` against the bench's `@agent_tools` requirements) would catch this class at validate-time in <2s, before any agent runs. Cheaper than catching it at run-time and clearer than the OpenRouter 404.

- **021 — Domain-tagged degrade policy.** When a reviewer with a domain tag (`security`, `correctness`, `tests`, …) fails on a PR whose marshal plan invoked that tag explicitly, the run shouldn't silently degrade — it should either substitute a same-domain alternate (a backup reviewer per role), escalate the synthesizer to flag the gap loudly in the final review, or fail the run entirely if the domain is load-bearing for the diff. The current synthesis is honest about partial coverage but easy to miss; a marshal-aware degrade policy would tighten it.

Both are out of scope for the immediate fix. They are listed here so the fix doesn't quietly close the bigger gap.
