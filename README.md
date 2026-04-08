# thinktank

Thin Pi bench launcher for research and code review.

ThinkTank defines named Pi agents, groups them into benches, launches them in
parallel against the current workspace, and writes raw artifacts. It does not
precompute semantic context, route through a workflow DSL, or parse agent prose
with regexes. Review benches can optionally run a planning agent first to pick
the reviewer subset and write a lightweight context pack.

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

export THINKTANK_OPENROUTER_API_KEY="your-key"

./thinktank research "analyze this codebase" --paths ./lib
./thinktank run research/quick --input "quick repo scan" --paths ./lib --no-synthesis
./thinktank review --base origin/main --head HEAD
```

## Usage

```bash
thinktank run <bench> --input "..." [options]
thinktank research "..." [options]
thinktank review [options]
thinktank review eval <contract-or-dir> [--bench <bench>]
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
| `--bench BENCH` | Bench override for `review eval` |

### Examples

```bash
# Fixed research bench
thinktank research "what is wrong with this architecture?" --paths ./lib

# Fast repo-aware research bench without an internal synthesizer
thinktank run research/quick --input "what changed in this subsystem?" --paths ./lib --no-synthesis

# Fixed review bench
thinktank review --base origin/main --head HEAD

# Replay frozen review workloads through a named bench
thinktank review eval ./tmp/review-run --bench review/default

# Explicit bench invocation with a subset of agents
thinktank run review/default --input "Review this branch" --agents trace,guard

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

- `research/quick`
- `research/default`
- `review/default`

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
  review/default:
    kind: review
    description: Fixed review bench
    agents: [trace, guard, atlas, proof]
    planner: marshal
    synthesizer: review-synth
    concurrency: 4
    default_task: Review the current change and report only real issues with evidence.

  research/default:
    kind: research
    description: Fixed research bench
    agents: [systems, verification, ml, dx]
    synthesizer: research-synth
```

Bench kinds:

- omit `kind` or use `default` for generic benches
- use `kind: review` for benches that should accept `--base`, `--head`, `--repo`, and `--pr`
- use `default_task` when a bench should run without stdin or `--input`

Example custom review bench:

```yaml
benches:
  review/security:
    kind: review
    description: Security-focused review bench
    agents: [guard]
    planner: marshal
    default_task: Review the current change for real security issues.
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
- `review/context.json` and `review/context.md` for review benches
- `review/plan.json` and `review/plan.md` for review benches
- `review/planner.md` when a planner agent runs
- `manifest.json` — run metadata and artifact index

`--json` prints the final run envelope to stdout after the bench completes. It
does not write a `report.json` artifact. For research benches, the synthesized
document lives in `synthesis.md` when a synthesizer is enabled.

ThinkTank records raw outputs and run metadata. It does not attempt to recover
structure from agent prose after the fact.

## Review Notes

- Review benches do not materialize a patch bundle. Reviewers are still expected
  to inspect the repo and git state themselves.
- ThinkTank may write a light review context pack and review plan before
  launching reviewers. These are orientation artifacts, not substitutes for
  repository exploration.
- `review/default` uses `marshal` as planner and synthesizes across the full reviewer roster.
- `--base`, `--head`, `--repo`, and `--pr` are orientation hints for the
  reviewers and synthesizer.
- Repository-local `agent_config/` is only loaded when
  `THINKTANK_TRUST_REPO_AGENT_CONFIG=1` is set.

## Replay Eval

`thinktank review eval` is intentionally narrow. It replays one or more saved
`contract.json` review workloads through a bench and writes fresh artifacts so
you can compare benches on the same frozen inputs. It does not impose an
automatic scoring framework.

## Development

```bash
mix test
mix format
mix compile --warnings-as-errors
mix escript.build
```
