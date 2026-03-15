# Project: thinktank

## Vision

Agent-first research tool that gets multiple AI perspectives on a question or problem. Sends context + instructions to multiple LLMs via OpenRouter and synthesizes their responses — turning model diversity into deeper understanding.

**North Star:** The research backbone for AI agents and engineers who need multiple perspectives, not just one model's opinion.
**Target User:** AI agents orchestrating research workflows; engineers who want diverse model perspectives on code, architecture, and design decisions.
**Key Differentiators:** Agent-composable CLI; single-key OpenRouter access to many models; synthesis that extracts signal from model disagreement; context-grounded analysis.

## Principles

- **Agent-first.** Thinktank is a tool for agents to call, not primarily a human-interactive CLI. Design for machine consumption, human readability is a bonus.
- **Perspective diversity is the product.** The value isn't any single model's output — it's the disagreement, convergence, and synthesis across models.
- **Grounded analysis only.** Models always see the actual context — no hallucination-prone "describe your problem" workflows.
- **One key, many minds.** OpenRouter as the single gateway means zero vendor lock-in and instant access to new models as they ship.
- **CLI-native composability.** Pipes, scripts, automation. A building block in larger agent workflows, not an island.
- **Minimal moving parts.** Single binary, single env var. Complexity in the model layer, simplicity in the tool layer.

## Philosophy

- Model diversity is a research methodology, not a feature. Different models catch different things.
- Synthesis > aggregation. Combining outputs into coherent insight is harder and more valuable than concatenation.
- Resilience over speed. Retry transient failures, degrade gracefully, never lose results.
- Ship what matters. Model registry freshness and output quality outweigh feature count.
- Elixir idioms: pattern matching, `with` chains for multi-step errors, deep modules with small public APIs.

## Domain Glossary

| Term | Definition |
|------|-----------|
| Perspective | A `{role, model, prompt}` struct assigned by the router |
| Router | `lib/thinktank/router.ex` — LLM-powered perspective generation |
| Quick mode | `lib/thinktank/dispatch/quick.ex` — parallel OpenRouter API calls |
| Deep mode | `lib/thinktank/dispatch/deep.ex` — Pi subprocess orchestration via MuonTrap |
| Synthesis | `lib/thinktank/synthesis.ex` — combines multiple model outputs into one response |
| Output | `lib/thinktank/output.ex` — kill-safe artifact writer with atomic manifest |
| OpenRouter | Single API gateway used for all model access (one key, unified interface) |
| Dry-run | Preview mode: shows plan without making API calls |

## Quality Bar

- [ ] `mix test` passes
- [ ] `mix format --check-formatted` clean
- [ ] `mix compile --warnings-as-errors` clean
- [ ] Conventional commit messages (`feat:`, `fix:`, `docs:`, `chore:`)

## Patterns to Follow

### Pattern Matching over Conditionals
```elixir
def handle({:ok, result}), do: process(result)
def handle({:error, reason}), do: {:error, reason}
```

### With Chains for Multi-step Errors
```elixir
with {:ok, perspectives} <- Router.generate_perspectives(instruction, paths),
     {:ok, results} <- Quick.dispatch(perspectives, instruction),
     {:ok, synthesis} <- Synthesis.synthesize(results, instruction) do
  {:ok, synthesis}
end
```

### Explicit Error Handling
```elixir
# Never suppress errors — handle every {:error, _} explicitly
case OpenRouter.chat(messages, model) do
  {:ok, response} -> {:ok, response}
  {:error, reason} -> {:error, "model #{model} failed: #{reason}"}
end
```

## History

Go v4 codebase archived on the [`v4-archive`](https://github.com/misty-step/thinktank/tree/v4-archive) branch (tag: `v4.0.0`).

---
*Last updated: 2026-03-15*
