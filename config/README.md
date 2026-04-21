# thinktank Configuration

ThinkTank loads typed bench configuration from:

1. built-in defaults
2. `~/.config/thinktank/config.yml`
3. `.thinktank/config.yml` in the current repository when `--trust-repo-config`
   or `THINKTANK_TRUST_REPO_CONFIG=1` is set

CLI flags override run-time input such as task text, paths, and review refs.

## Top-Level Shape

```yaml
providers:
  openrouter:
    adapter: openrouter
    credential_env: THINKTANK_OPENROUTER_API_KEY
    defaults:
      fallback_env: OPENROUTER_API_KEY

agents:
  trace:
    provider: openrouter
    model: x-ai/grok-4.20
    system_prompt: |
      You are trace, a correctness reviewer.
    task_prompt: |
      {{input_text}}
    tools: [bash, read, grep, find, ls]
    thinking_level: medium
    retries: 0
    timeout_ms: 600000

benches:
  research/quick:
    kind: research
    description: Fast repo-aware research bench
    agents: [systems, verification]

  review/default:
    kind: review
    description: Default review bench
    agents: [trace, guard, atlas, proof]
    planner: marshal
    synthesizer: review-synth
    concurrency: 4
    default_task: Review the current change and report only real issues with evidence.

  research/default:
    kind: research
    description: Default research bench
    agents: [systems, verification, ml, dx]
    synthesizer: research-synth
```

## Typed Specs

- `ProviderSpec`: provider id, adapter kind, credential env var, defaults
- `AgentSpec`: name, provider, model, system prompt, task prompt, tools,
  thinking level, retries, timeout
- `BenchSpec`: id, kind, description, agent list, optional synthesizer,
  concurrency, and optional `default_task`

## Bench Kinds

- `default`: generic bench behavior
- `research`: research-oriented built-in bench kind
- `review`: bench accepts `--base`, `--head`, `--repo`, and `--pr`

If a bench has a `default_task`, `thinktank run <bench>` can run without
stdin or `--input`.

## Built-In Benches

- `research/quick`
- `research/default`
- `review/default`

## Current Provider Support

- `openrouter`
