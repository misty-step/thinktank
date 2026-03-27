# thinktank Configuration

ThinkTank loads typed YAML configuration from:

1. built-in defaults
2. `~/.config/thinktank/config.yml`
3. `.thinktank/config.yml` in the current repository

CLI flags override run-time inputs such as workflow input text, paths, mode, and review refs.

## Top-Level Shape

```yaml
providers:
  openrouter:
    adapter: openrouter
    credential_env: THINKTANK_OPENROUTER_API_KEY
    defaults:
      fallback_env: OPENROUTER_API_KEY

agents:
  architecture-reviewer:
    provider: openrouter
    model: openai/gpt-5.4
    system_prompt: You are an architecture reviewer.
    prompt: "Review this change: {{input_text}}"
    tool_profile: review
    thinking_level: high
    retries: 1
    timeout_ms: 900000

workflows:
  code-review:
    description: Review the current branch against the base branch.
    default_mode: deep
    input_schema:
      required:
        - input_text
    stages:
      - name: prepare
        type: prepare
        kind: review_diff
      - name: route
        type: route
        kind: static_agents
        agents:
          - architecture-reviewer
      - name: fanout
        type: fanout
        kind: agents
      - name: emit
        type: emit
        kind: artifacts
```

## Typed Specs

- `ProviderSpec`: provider id, adapter kind, credential env var, defaults
- `AgentSpec`: name, provider, model, system prompt, prompt template, tool profile, thinking level, retries, timeout
- `WorkflowSpec`: id, description, input schema, default mode, ordered stage list
- `StageSpec`: `prepare`, `route`, `fanout`, `aggregate`, or `emit`, plus `kind`, `when`, retry, and concurrency

## Built-In Workflows

- `research/default`
- `review/cerberus`

## Current Provider Support

- `openrouter`

Provider specs are first-class in config, but the initial implementation only ships the OpenRouter adapter.
