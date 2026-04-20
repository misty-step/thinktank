# ThinkTank Repo Brief

## Vision & Purpose

ThinkTank is a thin Pi bench launcher for research and code review. Its job is
to define named agents and benches, launch them against the current workspace,
and record raw artifacts plus durable run metadata. It is built for other
agents and engineers to call as a dependable command plane, not as a semantic
workflow engine or a second direct-API path around Pi.

The product value is perspective diversity with inspectable artifacts. ThinkTank
should make multi-agent research and review reproducible, debuggable, and
operator-friendly without absorbing reasoning into the harness layer.

## Stack & Boundaries

- Language/runtime: Elixir/OTP application with an escript CLI
- CI/gate layer: Dagger module in `ci/` with Python entrypoint
- Runtime launch boundary: `lib/thinktank/executor/agentic.ex`
- Bench/config boundary: `lib/thinktank/builtin.ex`, `lib/thinktank/config.ex`,
  `lib/thinktank/engine/preparation.ex`
- Artifact/trace boundary: `lib/thinktank/run_store.ex`,
  `lib/thinktank/artifact_layout.ex`, `lib/thinktank/trace_log.ex`
- Review-specific layer: `lib/thinktank/review/context.ex`,
  `lib/thinktank/review/planner.ex`, `lib/thinktank/review/eval.ex`

ThinkTank owns launch, isolation, retries, timeouts, concurrency, traces, and
artifacts. Pi agents own repo exploration, git inspection, tool use, and
reasoning. The repo explicitly rejects semantic workflow DSLs, regex parsing of
agent prose, and bypass paths that duplicate Pi behavior.

## Load-Bearing Gate

`./scripts/with-colima.sh dagger call check` is the canonical local and
merge-readiness gate.

Every gate-adjacent skill must cite that exact command. It is the single source
of truth for "green enough to ship" and currently enforces:

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix credo --strict`
- Dialyzer
- shell and YAML hygiene
- gitleaks
- repo-owned security gate
- live model-ID validation
- architecture gate
- escript smoke
- `87%` coverage floor

Host-native `mix` commands are fallback debugging tools, not the gate.

## Invariants

- Primary branch is `master`.
- Release Please owns version bumps, changelog churn, and release PRs.
  Do not hand-edit `@version` in `mix.exs`, cut tags manually, or treat
  `CHANGELOG.md` as a scratchpad.
- Backlog truth lives in `backlog.d/`. Active items stay top-level, completed
  items move to `backlog.d/done/`, and every item needs a `Status:` field.
- The repo is local-first. Git hooks in `.githooks/` and the Dagger gate are
  load-bearing, not optional suggestions.
- `.claude/agents/*.md` are lens-only persona definitions. Model choice and
  reasoning tier belong to the caller/runtime, not the agent file.
- Model IDs must be verified against current repo-owned truth and the live
  validator path. Do not write model slugs from memory.
- ThinkTank QA is about launcher behavior, contracts, artifacts, and exits.
  Use cheap models for live QA unless premium reasoning quality is the feature
  under test.
- Evidence meant for humans must be visual when proof matters. Text logs are
  raw data, not proof.
- Documentation that captures durable repo identity must stay durable. Avoid
  sprint snapshots, issue-number narration, and stale version framing in
  long-lived docs.

## Known Debts

- Backlog 015: review-eval and finished review contract remain inconsistent.
- Backlog 016: run lifecycle still lacks a single explicit session owner.
- Backlog 017: review control-plane reduction to structured contracts is still
  open.
- Backlog 018: gate policy sources still have overlap that should be
  centralized.
- Backlog 020: `thinktank benches validate` still needs provider capability
  checks before launch.
- Backlog 021: review runs still need domain-tagged degrade policy when a
  marshal-invoked reviewer drops out.

Recurring failure modes from repo history and session memory:

- stale model IDs or stale model-selection assumptions
- shallow research fanout that routes to one source instead of many
- QA/demo evidence reported as text rather than screenshots or GIFs
- expensive QA model choices for plumbing validation
- operator docs drifting away from the actual thin-launcher architecture

## Terminology

- Agent: named Pi config with provider, model, prompts, and tools
- Bench: named set of agents with optional planner and synthesizer
- Planner: optional agent that selects or narrows reviewer participation
- Synthesizer: optional agent that writes the final research or review artifact
- Run contract: persisted input and execution context for one run
- Manifest: artifact index and run metadata for one run
- Scratchpad: append-only run or agent journal written during execution
- Trace: structured JSONL event stream for a run and optional global mirror
- Review context: lightweight git-derived orientation for review benches
- Review role/domain tag: bench metadata like `security`, `correctness`,
  `tests`, `interfaces`, `operability`

## Session Signal

Recurring user corrections:

- Verify model IDs against current registry truth; never trust memory.
- Keep `project.md` and similar docs durable; ephemeral state belongs
  elsewhere.
- Research means parallel fanout across multiple sources, not one-source
  lookup.
- QA for ThinkTank should default to cheap models, not flagship tiers.
- Proof for reviewers should be screenshots/GIFs when evidence matters.

Validated patterns the user keeps ratifying:

- Use `./scripts/with-colima.sh dagger call check` as the exact gate.
- Prefer thin boundaries over new orchestration layers.
- Treat ThinkTank as an agent-first command plane, not a user-facing workflow
  product.
- Use `backlog.d/` as the planning and execution queue.
- Keep release and versioning flow conventional and automated through
  Release Please.
