# Domain-Tagged Degrade Policy

Priority: medium
Status: ready
Estimate: L

## Goal

When a reviewer carrying a domain tag (e.g. `security`, `correctness`, `tests`) fails on a PR whose marshal plan invoked that domain explicitly, the review run loudly reflects the missing perspective — either by substituting a same-domain alternate, escalating the synthesizer to flag the gap in its final review, or failing the run when the domain is load-bearing for the diff — instead of silently degrading into a partial review that reads as complete.

## Non-Goals

- Rewriting the reviewer roster or marshal planner
- Adding a new planner stage between marshal and reviewer dispatch
- Building a dependency graph across domain tags (a flat tag list is enough to start)
- Gating non-review benches (research/default etc.) on domain coverage

## Constraints / Invariants

- The existing synthesis contract stays honest about partial coverage; this item raises the floor, it does not weaken today's partial reporting
- A substituted alternate reviewer must share the failed reviewer's domain tag — no silent cross-domain promotion
- "Fail the run" is reserved for cases where marshal explicitly invoked the domain for this diff; a generic reviewer dropping out is still a degrade, not a hard fail
- All three outcomes (substitute / escalate / fail) must be representable in the existing run-manifest and JSON envelope so downstream consumers can detect the event

## Repo Anchors

- `lib/thinktank/builtin.ex` — reviewer `review_role` metadata already encodes domain tags (`security`, `correctness`, `tests`, `interfaces`, ...); this item is the thing that gives those tags teeth
- `lib/thinktank/engine/runtime.ex` — synthesis orchestration path; degrade decisions land here
- `lib/thinktank/prompts/review.ex` — marshal plan prompt; may need to emit the invoked domain list into the plan artifact
- `lib/thinktank/prompts/synthesis.ex` — review-synth system prompt; the "escalate" path lives here
- `lib/thinktank/run_contract.ex` — persisted run contract extension for degrade-policy outcomes

## Evidence

Backlog 019's impact section: a security-themed PR (Apollo webhook HMAC + rate-limit hardening, +1201 LOC, 12 files) ran `review/default` with no security reviewer because `guard` 404'd. The synthesizer correctly noted "trace and pulse checked runtime behavior" but never named the missing security perspective. For a marshal-tagged security review, silently producing a no-security-reviewer synthesis is the failure mode thinktank should design against.

Today the run degrades quietly: `summary.json.status: degraded`, per-agent errors in their own artifacts, a synthesizer that is honest about what it saw but never flags the missing marshal-invoked domain. A downstream consumer caught the gap only because two other review tiers were running alongside; without those backstops, the shipped review would have silently lacked the security perspective on a security-themed change.

## Oracle

- [ ] Marshal plans that explicitly invoke a domain tag produce a run artifact recording that invocation (so the degrade policy has something to compare against)
- [ ] When a reviewer carrying an invoked domain fails, the runtime picks one of three deterministic outcomes (substitute / escalate / fail), records which was chosen, and never returns `status: degraded` with the domain gap buried in a per-agent error file
- [ ] A same-domain substitute reviewer roster exists in `builtin.ex` (or resolves from the existing roster by domain tag) so substitution is a data lookup, not new logic
- [ ] Integration test asserts: a bench run where `guard` is forced to fail on a security-tagged marshal plan produces either a substituted security reviewer or a synthesis whose final output names the missing security perspective in its top-level summary (not only in a footnote)
- [ ] `--json` payload exposes the chosen degrade outcome under a typed field so `/code-review` and similar downstream consumers can detect it without prose-parsing

## Notes

Depends partially on 020 — a capability-aware validate would prevent a known category of reviewer failure (model lacks tool support) from triggering degrade-policy in the first place. But 021 stands on its own: provider outages, rate-limit 429s, and long-tail per-model errors will still drop reviewers at run-time even with a perfect validate step. The policy needs to exist either way.

Parked from the 019 notes: this item carries the "domain-tagged degrade policy" follow-up that the fix deferred as out-of-scope.
