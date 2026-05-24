# Agent Composition Vision

Last updated: 2026-05-22

## Thesis

ThinkTank should become the local command plane for governed agent compositions:
any caller can define a bounded team of agents, launch them against a workspace,
watch and steer the run, preserve the evidence, and synthesize results without
turning the system into a semantic workflow engine.

The form factor is **agent tmux over a portable Benchfile contract**.

- Agent tmux: a local operator surface for live runs, status, feedback,
  cancellation, retry, and synthesis.
- Benchfile: a declarative, validated composition contract for providers,
  models, personas, tools, tasks, reducers, and expected artifacts.
- Command plane: ThinkTank owns launch, bounds, lifecycle, artifacts,
  coverage, cost, replay, and evaluation.

ThinkTank does not own agent reasoning, repo interpretation, editor workflows,
or a second direct model-runtime path that bypasses Pi-family agents.

## Why This Is The Right Shape

The user need is not "run many agents." The real need is to make multi-agent
work governable enough that humans, CI, and other agents can trust it.

Current ThinkTank already has the hard local spine:

- `lib/thinktank/bench_spec.ex` and `lib/thinktank/agent_spec.ex` define flat
  bench and agent contracts.
- `lib/thinktank/engine/runtime.ex` runs a planner-selected agent set and a
  final synthesizer.
- `lib/thinktank/executor/agentic.ex` owns Pi subprocess launch, retries,
  timeouts, per-agent homes, prompt files, and captured output.
- `lib/thinktank/run_store.ex`, `lib/thinktank/trace_log.ex`, and
  `lib/thinktank/run_inspector.ex` preserve run state and make it inspectable.

The gap is that this spine is still a flat bench launcher. It can launch
research and review benches, but it cannot yet express or manage arbitrary
agent compositions with explicit stage lineage, feedback injection, live
operator control, and promotion into evals.

## External Evidence

### Pi And Oh My Pi

Pi's monorepo positions itself as an agent harness with an interactive coding
agent, agent runtime, and multi-provider LLM API:
https://github.com/earendil-works/pi

Oh My Pi is an active Pi fork and terminal coding-agent platform. On
2026-05-22, `can1357/oh-my-pi` had release `v15.2.4`, MIT license, and
public README claims around first-class subagents, structured task output,
LSP/DAP, hashline edits, internal URL schemes, session memory, MCP, RPC, ACP,
and an SDK:
https://github.com/can1357/oh-my-pi

The most relevant OMP details for ThinkTank are not the interactive coding
surface. They are the embeddable runtime surfaces:

- RPC mode is JSONL over stdio and starts with a ready frame:
  https://github.com/can1357/oh-my-pi/blob/main/docs/rpc.md
- SDK entry point is `createAgentSession()`, which exposes event streaming,
  tool wiring, model/auth control, and session management:
  https://github.com/can1357/oh-my-pi/blob/main/docs/sdk.md
- Task agents support discovered agent definitions, per-task assignments,
  optional schemas, isolated workspaces, `agent://` output handles, async
  progress, and structured result collection:
  https://github.com/can1357/oh-my-pi/blob/main/docs/tools/task.md

Implication: OMP should influence ThinkTank's runner adapter and artifact
contract, but it should not replace ThinkTank's run/evidence command plane.

### Agent Harness Best Practices

OpenAI's Agents SDK docs distinguish direct model clients from agent
applications that own orchestration, tool execution, approvals, and state, and
point builders toward specialist ownership, sandboxing, guardrails, results,
observability, and workflow evals:
https://developers.openai.com/api/docs/guides/agents

OpenAI's agent-building guide frames guardrails as layered defenses and calls
out tool safeguards based on read/write access, reversibility, permissions, and
impact:
https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf

Recent harness-engineering research emphasizes reproducibility, sandbox reset,
trace-native evaluation, whole model-tool-environment replay, and the
cost-quality-speed tradeoff:
https://openreview.net/pdf/f358711a95aaaf61fdeffd4ef3fc60fba9b8da57.pdf

`Code as Agent Harness` identifies open challenges that map directly to
ThinkTank's roadmap: evaluation beyond final task success, incomplete feedback,
regression-free harness improvement, consistent shared state across agents, and
human oversight for risky actions:
https://arxiv.org/abs/2605.18747

The Agent Control Protocol paper is useful as a warning: per-request policy is
not enough for agent systems because risk accumulates across traces. ThinkTank
should model run-level and agent-level admission decisions as explicit
artifacts, not prompt advice:
https://arxiv.org/abs/2603.18829

## Product Principles

1. Artifact contracts beat orchestration cleverness.
2. Composition is data first, runtime second, UI third.
3. Every agent has visible identity, model, provider, tools, timeout, role,
   task, and output expectations.
4. Every run has replayable inputs: Benchfile, config provenance, prompts,
   model roster, workspace, refs, env facts, and run state.
5. Feedback is a first-class event, not an untracked chat message.
6. Synthesis is a reducer over artifacts, not a truth oracle.
7. Policy lives outside agent self-reporting: coverage, permissions, admission,
   cost, and terminal status are computed by ThinkTank.
8. OMP/Pi are runner substrates and exemplars, not the product boundary.

## Ultimate Form Factor

## Designs Considered

The research pass considered five structurally different end states.

| Design | Value proposition | Best use | Why not alone |
| --- | --- | --- | --- |
| Agent tmux | Launch arbitrary agent teams, watch streams, interrupt, retry, inject feedback, and synthesize. | Solo operator and local engineering workflows. | Needs a portable contract underneath or it becomes a bespoke UI over subprocesses. |
| Benchfile protocol | Any agent or repo can define a portable composition as data and hand it to ThinkTank. | Harness authors, repo maintainers, CI, and other agents. | Can accrete into a stage-graph DSL if not kept deliberately small. |
| Local agent control plane | A daemon/API every local harness can call for bounded execution and run discovery. | Codex, Claude, Pi, editor clients, shell scripts, CI. | Daemon reliability and security become the product before the contracts are mature. |
| Review/research mission room | Human steers a live composition and approves final synthesis from evidence. | Engineering leads, reviewers, researchers, consultants. | Risks optimizing for dashboards instead of reproducible run contracts. |
| Bench lab / evaluation foundry | Build, replay, compare, and promote agent compositions against frozen corpora. | Teams tuning review/research benches over time. | Can become academic if it does not stay connected to live launches. |

Recommended sequence: start with agent tmux plus Benchfile. The local control
plane, mission room, and bench lab are later surfaces once the run graph,
coverage, permission, and evaluation contracts are solid.

## Fit With The Rest Of The Stack

ThinkTank should be the shared local run substrate, not the universal agent UI.

- **Codex / Claude / Pi / OMP:** callers and possible runners. They can launch
  or consume ThinkTank runs, but ThinkTank should not absorb their interactive
  shells, memories, editor state, or tool catalogs.
- **Spellbook:** governance and work-loop layer. Spellbook skills shape,
  deliver, review, verify, and record receipts using ThinkTank evidence, while
  ThinkTank stays focused on local run contracts and artifacts.
- **CI:** non-interactive consumer. CI should call compact review/eval commands
  and fail on typed status, coverage, and blocking-finding contracts.
- **Curb / local supervision:** outer safety rail. Curb-style process limits and
  watchdog behavior can bound long-running agents, while ThinkTank records the
  per-run lifecycle and evidence.
- **Daybook / knowledge workflows:** downstream memory surface. Durable reports
  and structured findings can be saved or indexed after the run, but ThinkTank
  should not become the vault.

This gives the broader system a clean split:

```text
Spellbook decides what work/evidence is required.
ThinkTank launches and records bounded agent compositions.
Pi/OMP/Codex/Claude do the agent reasoning and tool work.
Curb supervises local process risk.
Daybook preserves long-lived human knowledge.
```

### CLI

```sh
thinktank compose run Benchfile.yml --input "Review this branch"
thinktank compose attach <run-id>
thinktank compose feedback <run-id> --to security --message "Focus on auth bypass"
thinktank compose synthesize <run-id>
thinktank compose abort <run-id> --agent security
thinktank runs compare <old-run> <new-run>
```

### TUI

The TUI is the "agent tmux" view:

- one pane per agent or stage
- live status, cost, duration, retry count, and last event
- feedback and abort controls
- artifact handles and structured outputs
- final reducer/synthesis pane

### Filesystem Contract

Runs remain inspectable without the TUI:

```text
run/
  contract.json
  graph.json
  task.md
  prompts/
  agents/
  stages/
  feedback/events.jsonl
  trace/events.jsonl
  coverage.json
  manifest.json
  synthesis.md
```

## Benchfile Shape

Benchfile is not a workflow DSL. It is a composition declaration.

```yaml
version: 1
kind: composition
description: Review this branch with specialized reviewers and a final reducer.

runners:
  default:
    adapter: pi-cli
    binary: pi

agents:
  security:
    provider: openrouter
    model: x-ai/grok-4.20
    role: security
    tools: [bash, read, grep, find, ls]
    timeout_ms: 300000
    output:
      schema: review_finding_list

  tests:
    provider: openrouter
    model: openai/gpt-5.4-mini
    role: tests
    tools: [bash, read, grep, find, ls]
    timeout_ms: 300000

stages:
  - id: review
    fanout: [security, tests]
    reducer: review-synth
    coverage:
      required_roles: [security, tests]

feedback:
  allow_operator_messages: true
  events_artifact: feedback/events.jsonl
```

Allowed evolution:

- ordered stages
- fanout groups
- reducers/synthesizers
- required coverage roles
- runner adapters
- permission policy references

Forbidden evolution:

- arbitrary conditionals
- loops
- user-authored code
- semantic phase graphs
- prose-parsed dependencies

## Roadmap

### Phase 1: Governed Review Spine

Ship the existing direction:

1. `026-add-review-coverage-contract`
2. `024-add-first-class-focused-review-benches`
3. `027-add-bench-evaluation-corpus`
4. `030-add-ci-review-mode`
5. `028-add-run-compare-command`
6. `029-add-static-run-report-artifact`

This makes current review/research benches trustworthy before adding arbitrary
composition.

### Phase 2: Composition Contract

Add a portable composition file while keeping existing benches compatible:

1. Define Benchfile schema and validator.
2. Add run graph metadata to `contract.json` / `manifest.json`.
3. Persist stage lineage and artifact edges.
4. Expose `thinktank compose validate` and `thinktank compose run`.

### Phase 3: Runner Adapter Boundary

Lift Pi launch into a first-class adapter protocol:

- `pi-cli` preserves current behavior.
- `pi-rpc` uses JSONL stdio when stable enough.
- `omp-rpc` remains experimental and version-pinned.

Adapters must emit the same ThinkTank result shape. They cannot change bench or
composition semantics.

### Phase 4: Agent Tmux

Add an operator surface after the contract is stable:

- attach/detach
- feedback events
- per-agent abort/retry
- synthesis replay
- static report export

### Phase 5: Bench Lab

Close the improvement loop:

- promote real runs into eval cases
- compare model/runner/bench variants
- benchmark quality/cost/latency/coverage
- publish bench packs as validated config bundles

## Backlog Implications

The current backlog covers much of Phase 1. Missing work should be tracked as:

- Benchfile composition contract
- Pi-family runner adapter
- live agent room / agent tmux
- runner permission and supervision policy

Those items should remain downstream of the coverage/eval spine unless they are
shaped as small spikes.
