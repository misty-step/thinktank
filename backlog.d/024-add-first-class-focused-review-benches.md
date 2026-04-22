# Add First-Class Focused Review Benches

Priority: medium
Status: ready
Estimate: M

## Goal
Code review becomes easier to invoke correctly because common operator intents ship as named benches — e.g. security, tests, architecture, runtime risk — instead of requiring manual `--agents` overrides or ad-hoc roster knowledge.

## Non-Goals
- Replacing `review/default`
- Building a dynamic workflow DSL or user-authored planner language
- Changing the thin-launcher boundary
- Expanding into write-capable implementation benches in the same change

## Constraints / Invariants
- Focused review benches remain plain bench definitions with the existing planner/synthesizer model; no new execution concepts
- Bench naming must reflect operator intent and be discoverable via `thinktank benches list`
- Focused benches should reuse the same review contract, JSON envelope, and degrade policy as `review/default`
- No bench should silently weaken domain coverage; this item depends on `020` and `021` to keep focused benches honest

## Repo Anchors
- `lib/thinktank/builtin.ex`
- `lib/thinktank/prompts/review.ex`
- `lib/thinktank/cli/parser.ex`
- `README.md`
- `backlog.d/020-capability-aware-benches-validate.md`
- `backlog.d/021-domain-tagged-degrade-policy.md`

## Oracle
- [ ] Built-in config exposes at least three first-class focused review benches, such as `review/security`, `review/tests`, and `review/architecture`
- [ ] `thinktank benches list` and `thinktank benches show` present the new benches clearly
- [ ] `README.md` explains when to use each focused review bench instead of `review/default`
- [ ] Focused benches participate in the same capability validation and degrade-policy checks as `review/default`
- [ ] Automated coverage proves focused bench resolution and output contracts without introducing new execution paths

## Notes
Today ThinkTank has only one built-in review bench and pushes operator intent into `--agents` overrides or repository-local config. That is too coarse for the most common review asks.

This item adds product value without adding orchestration complexity: it packages the existing reviewer roster into better named benches so operators can ask for the right review directly.
