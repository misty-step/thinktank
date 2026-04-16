---
name: model-research
description: |
  Monthly scan of LLM releases with OpenRouter emphasis and Thinktank-fit analysis.
  Fans out across OpenRouter catalog, vendor changelogs, benchmarks, and social vibe-check;
  produces a report on what shipped, how it's landing, cost-in-Thinktank-context, and
  whether to fold into the agent catalog.
  Use when: "what models are out", "latest models", "model research", "monthly model scan",
  "new on OpenRouter", "should we swap X for Y", "vibe check on <model>",
  "model release report", "trinity ace" (or any unfamiliar model name — check before guessing).
argument-hint: "[--focus <vendor>] [--window <days>]"
allowed-tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Agent, Write
---

# Model Research

Produce a dated report on recent model releases with explicit Thinktank-fit
recommendations. Default window: **last 30 days** from the current date
(see `currentDate` in context, or `date +%Y-%m-%d`).

## Provider preferences (Thinktank-specific)

**Favored providers** (tiebreaker preference, not exclusive):
- Google (Gemini 3, Gemini 3.1 family — `google/gemini-3*`)
- Z.ai / Zhipu (`z-ai/*`)
- MiniMax (`minimax/*`)
- Arcee AI (`arcee-ai/*`, especially the Trinity line)
- xAI (`x-ai/grok-*`)

When two candidates are comparable, pick the favored-provider one. Don't
force favored providers into roles they're genuinely bad at.

**Price-tier rules** (the real gate, not provider names):
- **>$25/M output tokens**: instant ban. Currently catches `claude-opus-4.6`
  ($150/M), `claude-opus-4.6-fast` ($150/M), `gpt-5.4-pro` ($180/M). Don't
  propose these for any role.
- **$15–$25/M output tokens**: "look very closely." Justify in the report
  why this role needs a premium tier. Favor a cheaper alternative unless
  the evidence is concrete (benchmark lead, capability only this tier has).
- **≤$15/M output tokens**: normal consideration. No special treatment.
- Input prices matter much less — reviewer turns are ~4× input / 1× output
  by volume, but output-token pricing dominates bench cost.

**Not favored, not banned** (only recommend if materially better than a
favored-provider alternative): Mistral, OpenAI mini/nano tiers, Anthropic
Sonnet/Haiku tiers, Qwen, Kwaipilot, Xiaomi, NVIDIA, ByteDance, Inception,
Moonshot. These already appear in `builtin.ex`; don't churn them out
unless there's a real upgrade.

**Mistral in particular**: user preference is to avoid Mistral. Skip it.

## Principles

- **Fan out, don't serial search.** Dispatch parallel subagents: OpenRouter
  catalog, vendor changelogs, benchmarks, social vibe. One agent per lane.
- **Benchmarks lie alone.** Artificial-analysis, LMArena, aider, SWE-bench
  each have biases. Cross-reference ≥2 sources per claim.
- **Vibe ≠ benchmark.** A model can top leaderboards and feel bad in agent
  loops (slow, hallucinates tools, ignores system prompts). Report both.
- **Cost-in-Thinktank, not cost-per-million.** A review bench runs 10
  agents in parallel. Price the bench, not the token.
- **Model IDs are load-bearing.** Thinktank validates IDs against OpenRouter
  in CI (see `Thinktank.ModelValidation`). Every recommended ID must resolve
  on `openrouter.ai/api/v1/models` today, not "should be soon."

## Sources (authoritative order)

1. **OpenRouter catalog** — `https://openrouter.ai/api/v1/models` (JSON, no
   auth) is ground truth for what's available via OR today, including pricing
   (`pricing.prompt`, `pricing.completion`, in $/token), context length, and
   supported modalities. Also browse `https://openrouter.ai/models?order=newest`.
2. **Vendor primary sources** (last 30d releases, changelogs, model cards):
   - Anthropic: `anthropic.com/news`, `docs.anthropic.com/en/docs/about-claude/models`
   - OpenAI: `openai.com/index` (filter "release notes"), model cards on platform docs
   - Google DeepMind: `deepmind.google/discover/blog`, `ai.google.dev/gemini-api/docs/models`
   - xAI: `x.ai/news`, `docs.x.ai`
   - Mistral: `mistral.ai/news`
   - Meta: `ai.meta.com/blog`
   - DeepSeek, Qwen/Alibaba, Zhipu (GLM), Moonshot (Kimi), MiniMax, 01.AI —
     check HuggingFace org pages and their own blogs/changelogs.
3. **Benchmarks (triangulate)**:
   - `artificialanalysis.ai` — throughput, cost, quality index. Good for
     spotting new entrants; weak on agent tool-use.
   - `lmarena.ai` — blind preference; heavily style-biased.
   - `aider.chat/docs/leaderboards/` — real coding edit benchmark; closest
     proxy for Thinktank reviewer workloads.
   - `swebench.com` — agentic coding; look at Verified split only.
   - `livebench.ai` — less gamed; updated monthly.
4. **Vibe check**:
   - r/LocalLLaMA (HuggingFace-adjacent releases, open-weight vibe)
   - X/Twitter: search `from:skcd42 OR from:swyx OR from:simonw OR from:ArtificialAnlys`
     plus the model name
   - Hacker News front page for the launch thread
   - simonwillison.net/tags/llms/ for writeups
5. **Thinktank internals** (for fit analysis):
   - `lib/thinktank/builtin.ex` — current model bindings per agent role
   - `lib/thinktank/model_validation.ex` — how IDs are validated
   - `agent_config/AGENTS.md` — Pi research agent prompt

## Fan-out dispatch

Launch these **in parallel** (single message, multiple Agent calls):

| Lane | Subagent | Output |
|------|----------|--------|
| Catalog | Explore | New IDs on OR in window, with pricing + context length |
| Vendor | Explore | Primary-source launch posts, dated, with links |
| Benchmarks | Explore | Scores across aider/livebench/SWE-bench/AA for new entrants |
| Vibe | general-purpose (WebSearch/WebFetch) | Community reception, practitioner takes |
| Thinktank-fit | Explore | Which current bindings in `builtin.ex` are beatable on price or quality; capability gaps (long-context, speculative-decoding, tool-use reliability) |

Each subagent must return: facts with source URLs, dated, under 400 words.
Synthesize on the main thread — do not ask a subagent to write the final report.

## Cost framing for Thinktank

When pricing a swap candidate, compute against real bench shapes:

- **research/quick** — 2 agents, 1 synth-free turn. Typical spend: small.
- **research/default** — 4 research agents + 1 synthesizer. Cost dominated
  by synthesizer if it's gpt-5.4-tier.
- **review/default** — 10 reviewers + marshal + synthesizer. **This is the
  bench where cost optimizations actually matter.** A 2x cheaper reviewer
  saves 10x at the bench level.

Report candidate costs as: `$X / review bench / typical run` and
`$Y / research bench / typical run`, estimating ~8K input / ~2K output per
agent turn unless you have better numbers from artifacts.

## Report format

Write to `.artifacts/model-research/YYYY-MM-DD.md`. Structure:

```
# Model Research — <date>

## TL;DR
3–5 bullets. Ship/skip/watch. Explicit swap recommendations.

## What shipped (last 30d)
Table: Model | Vendor | OR ID | Context | $in/$out | Released
Only models that appear in OpenRouter catalog today.

## Reception
One paragraph per notable model. Cite X handles, HN threads, r/LocalLLaMA.

## Benchmarks
Table with aider, livebench, SWE-Bench Verified, AA Quality Index.
Flag gaming / caveats inline.

## Vibe check
Qualitative: agent-loop reliability, system-prompt adherence, tool-use,
refusal behavior, speed. Source each claim.

## Cost in Thinktank context
Per-bench dollar estimates. Compare vs. incumbent.

## Fold-in recommendations
For each current agent binding in builtin.ex that has a better candidate:
- Agent role (e.g., "atlas")
- Current: <id> at <$>
- Proposed: <id> at <$>
- Evidence: <benchmark + vibe>
- Risk: <what breaks if we swap>
- Action: PR-sized change or "watch for 2 more weeks"

## Capability gaps / new vectors
Have any new capabilities emerged that Thinktank doesn't exploit?
Examples: 1M+ context for whole-repo synth, native tool-use agents,
on-device reasoning for local-first mode, speculative decoding for
latency-bound benches. Each: concrete Thinktank feature idea + rough sizing.

## Open questions
Things worth another pass next cycle.
```

## Gotchas

- **OpenRouter aliases shift.** `anthropic/claude-sonnet-4.6` today may be
  repointed tomorrow. Always record the resolved ID + canonical slug.
- **`:free` and `:floor` variants** exist on OR — note rate limits and the
  fact that they route through third-party providers with different privacy.
- **"Available soon" ≠ available.** If it's not in `/api/v1/models`, it
  doesn't exist for Thinktank purposes.
- **Preview / experimental models** (e.g., `-preview`, `-exp`) get yanked.
  Never bind a production reviewer to a preview ID.
- **LMArena style bias.** A model can win Arena by being chatty and emoji-laden
  while being useless in a JSON-returning reviewer role.
- **Benchmark staleness.** Aider/SWE-Bench often trail releases by weeks.
  Absence of a score ≠ bad; note it as "unmeasured."
- **Don't trust vendor claims of "matches GPT-X."** Every launch post says
  this. Look for third-party replication within the window.
- **Chinese-lab models on OR are proxied.** Data-residency caveats apply;
  flag for `guard` / `sentry` roles if relevant.
- **"Trinity Ace"-type names.** If the user names a model you don't
  recognize, check OpenRouter and vendor sites before speculating. A
  hallucinated recommendation here pollutes `builtin.ex` and breaks CI.

## Quick commands

```bash
# Live OpenRouter catalog (JSON)
curl -s https://openrouter.ai/api/v1/models | jq '.data[] | {id, context_length, pricing, created}'

# Filter: models created in last 30 days
curl -s https://openrouter.ai/api/v1/models \
  | jq --arg cutoff "$(date -v-30d +%s)" \
       '.data[] | select(.created > ($cutoff|tonumber)) | {id, created, pricing}'

# Current Thinktank bindings
grep -nE '"[a-z0-9-]+/[a-z0-9.-]+"' lib/thinktank/builtin.ex
```

Use `date -v-30d +%s` on macOS; `date -d '30 days ago' +%s` on Linux.
