# thinktank

Thin Pi bench launcher for research and code review.

ThinkTank defines named Pi agents, groups them into benches, launches them in
parallel against the current workspace, and writes raw artifacts. It does not
precompute semantic context, route through a workflow DSL, or parse agent prose
with regexes.

Built with Elixir/OTP.

## Philosophy

- Workspace is context. Run ThinkTank in the repo you want agents to inspect.
- Optional flags like `--paths`, `--base`, `--head`, `--repo`, and `--pr` only
  orient the agents. They are not substitutes for agent exploration.
- ThinkTank owns launch, sandboxing, concurrency, timeouts, and artifacts.
- Pi agents own repo exploration, git inspection, and reasoning.
- If you feel tempted to add semantic phases, handoffs, or prose parsers, you
  are probably doing work in the wrong layer.

## Quick Start

```bash
mix deps.get
mix escript.build

export OPENROUTER_API_KEY="your-key"

./thinktank research "analyze this codebase" --paths ./lib
./thinktank review --base origin/main --head HEAD
```

## Usage

```bash
thinktank run <bench> --input "..." [options]
thinktank research "..." [options]
thinktank review [options]
thinktank benches list|show|validate
```

`workflows list|show|validate` is still accepted as a compatibility alias for
`benches`.

### Options

| Flag | Description |
|------|-------------|
| `--input TEXT` | Task text |
| `--paths PATH` | Point the bench at paths in the workspace (repeatable) |
| `--agents LIST` | Comma-separated agent override for the selected bench |
| `--json` | Output JSON |
| `--output, -o` | Output directory |
| `--dry-run` | Resolve the bench without launching agents |
| `--no-synthesis` | Skip the synthesizer agent |
| `--trust-repo-config` | Trust `.thinktank/config.yml` in the current repository |
| `--base REF` | Review base ref |
| `--head REF` | Review head ref |
| `--repo REPO` | Review repo owner/name |
| `--pr N` | Review pull request number |

### Examples

```bash
# Fixed research bench
thinktank research "what is wrong with this architecture?" --paths ./lib

# Fixed review bench
thinktank review --base origin/main --head HEAD

# Explicit bench invocation with a subset of agents
thinktank run review/cerberus --input "Review this branch" --agents trace,guard

# Show bench configuration
thinktank benches show research/default
```

## Configuration

ThinkTank loads configuration with this precedence:

1. built-in defaults
2. `~/.config/thinktank/config.yml`
3. `.thinktank/config.yml` in the current repository when `--trust-repo-config`
   or `THINKTANK_TRUST_REPO_CONFIG=1` is set

Built-in benches:

- `research/default`
- `review/cerberus`

Config shape:

```yaml
providers:
  openrouter:
    adapter: openrouter
    credential_env: THINKTANK_OPENROUTER_API_KEY

agents:
  trace:
    provider: openrouter
    model: x-ai/grok-4.1-fast
    system_prompt: |
      You are trace, a correctness reviewer.
    task_prompt: |
      {{input_text}}
    tools: [bash, read, grep, find, ls]

benches:
  review/cerberus:
    description: Fixed review bench
    agents: [trace, guard, atlas, proof]
    synthesizer: review-synth
    concurrency: 4
```

## Artifacts

Each run writes:

- `contract.json` — resolved bench contract
- `task.md` — task text and pointed paths
- `agents/*.md` — raw agent outputs
- `prompts/*.md` — rendered prompts passed to Pi
- `summary.md` — synthesizer output when enabled
- `synthesis.md` for research benches
- `review.md` for review benches
- `manifest.json` — run metadata and artifact index

ThinkTank records raw outputs and run metadata. It does not attempt to recover
structure from agent prose after the fact.

## Review Notes

- `review/cerberus` does not materialize a diff bundle. Reviewers are expected
  to inspect the repo and git state themselves.
- `--base`, `--head`, `--repo`, and `--pr` are orientation hints for the
  reviewers and synthesizer.
- Repository-local `agent_config/` is only loaded when
  `THINKTANK_TRUST_REPO_AGENT_CONFIG=1` is set.

## Development

```bash
mix test
mix format
mix compile --warnings-as-errors
mix escript.build
```
