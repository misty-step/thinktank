# AGENTS.md

Map, not manual.

## Stack & Boundaries

ThinkTank is a thin Pi bench launcher for research and review.

- CLI surface: `lib/thinktank/cli.ex`
- Bench resolution and launch: `lib/thinktank/engine.ex`
- Built-in benches and agents: `lib/thinktank/builtin.ex`
- Pi subprocess runner: `lib/thinktank/executor/agentic.ex`
- Artifacts and manifests: `lib/thinktank/run_store.ex`
- Canonical artifact paths: `lib/thinktank/artifact_layout.ex`
- Trace and durable local logs: `lib/thinktank/trace_log.ex`
- Review planning and replay: `lib/thinktank/review/planner.ex`,
  `lib/thinktank/review/eval.ex`
- Container gate: `ci/` plus thin wrappers in `.github/workflows/`

What it is not:

- Not a semantic workflow engine
- Not a stage graph DSL
- Not a prose parser
- Not a second direct-API path that bypasses Pi

## Ground Truth

- Product and operator framing: `README.md`, `CONTRIBUTING.md`, `CLAUDE.md`
- Bench and agent truth: `lib/thinktank/builtin.ex`, `agent_config/`
- Run artifact contract: `lib/thinktank/run_store.ex`,
  `lib/thinktank/artifact_layout.ex`, `lib/thinktank/trace_log.ex`
- Review contract and replay: `lib/thinktank/review/planner.ex`,
  `lib/thinktank/review/eval.ex`
- Active backlog and debt map: `backlog.d/`

Training data lies. Read these files before asserting how the repo works.

## Gate Contract

`./scripts/with-colima.sh dagger call check` is the canonical local and
merge-readiness gate.

It enforces formatting, compile warnings as errors, `credo --strict`,
Dialyzer, shell/YAML hygiene, gitleaks, the repo-owned security gate, the
harness-agent gate for `.claude/agents/*.md`, live model-ID validation, the
architecture gate, escript smoke, and an `87%` coverage floor.

Use `mix test` and `mix compile --warnings-as-errors` only as targeted fallback
or debugging gates. Native hooks live in `.githooks/` and are installed by
`./scripts/setup.sh`.

## Invariants

- Primary branch is `master`.
- Release Please owns version bumps, changelog churn, and release PRs.
- Backlog truth lives in `backlog.d/`; completed items move to `backlog.d/done/`.
- Workspace is context. Launch, sandbox, timeout, and record in Elixir.
- Explore and reason in Pi. Do not compensate with extra harness logic.
- Model IDs must be validated against live repo-owned truth, not memory.
- Regex over agent prose, semantic phases, precomputed review bundles, and
  extra prompt scaffolding are all smell tests for the wrong layer.

## Harness Layout

Canonical shared skill root: `.agent/skills/`

| Layer | Path | Role |
|---|---|---|
| Shared skills | `.agent/skills/` | Canonical spellbook-tailored skills for this repo |
| Claude bridge | `.claude/skills/` | Symlink bridge to shared skills plus repo-local scaffolded `demo` and `qa` |
| Codex bridge | `.codex/skills/` | Symlink bridge so Codex resolves the same skill bodies |
| Pi bridge | `.pi/skills/` | Symlink bridge so Pi resolves the same skill bodies |
| Claude agents | `.claude/agents/` | Repo-local lenses only; model choice belongs to runtime |

Per-harness settings:

- Claude Code: `.claude/settings.local.json` (git-ignored, local only)
- Codex: `.codex/config.toml`
- Pi: `.pi/settings.json`

Repo-local scaffolded skills remain:

- `.claude/skills/demo/` — CLI-focused demo capture for ThinkTank
- `.claude/skills/qa/` — CLI behavior verifier, not browser QA

They are bridged into Codex and Pi so invocation is harness-neutral even
though their authored source still lives under `.claude/skills/`.

## Skill Index

Shared spellbook-tailored skills installed here:

| Skill | What It Means Here |
|---|---|
| `ci` | Drive `./scripts/with-colima.sh dagger call check` green and strengthen the gate without lowering thresholds |
| `code-review` | Run the philosophy bench plus ThinkTank review benches against `master...HEAD`, with special focus on launcher-boundary regressions |
| `deliver` | Take one `backlog.d/` item to merge-ready code, stopping short of push, merge, or deploy |
| `deps` | Curated Elixir dependency maintenance around `mix.exs` / `mix.lock`, with special care for `muontrap` and artifact-contract deps |
| `diagnose` | Debug trace, artifact, runtime, and model-validation failures using real run artifacts and logs before touching prompts |
| `flywheel` | Outer loop over `backlog.d/` that composes deliver, land, deploy/monitor no-ops, and reflect without adding orchestration state |
| `groom` | Backlog shaping around thin-launcher debt and command-plane simplification, not net-new workflow machinery |
| `implement` | TDD implementation against a shaped packet using Elixir tests and the Dagger gate as the merge-readiness backstop |
| `model-research` | OpenRouter-focused model scan filtered for ThinkTank reviewer/research bench fit |
| `refactor` | Simplify review/runtime/control-plane hotspots without introducing new orchestration layers |
| `reflect` | Post-work codification and harness hardening |
| `research` | Repo-aware multi-source research, not one-source lookup |
| `ship` | Final-mile landing for a settled branch: archive shipped tickets under `backlog.d/done/`, merge to `master`, then run `/reflect cycle` with harness edits on `reflect/<cycle-id>` |
| `settle` | Land a clean branch to `master` while respecting hooks, Conventional Commits, and Release Please |
| `shape` | Turn thin-launcher-safe ideas into context packets with executable oracles |
| `yeet` | Commit and push intentionally without `--no-verify` or stray workspace junk |

## Agent Index

Installed repo-local lenses:

| Agent | Role |
|---|---|
| `beck` | TDD discipline and test-first pressure |
| `builder` | Heads-down implementation against a context packet |
| `carmack` | Shippability and anti-overengineering lens |
| `critic` | Skeptical grading of implementation output |
| `grug` | Complexity and abstraction minimization |
| `ousterhout` | Deep-module and information-hiding review |
| `planner` | Context-packet and decomposition work |

These files must not hardcode model IDs, model families, or reasoning tiers.

## Debt Map

- `backlog.d/015-fix-review-eval-and-finished-review-contract.md`
- `backlog.d/016-add-run-session-and-single-lifecycle-owner.md`
- `backlog.d/017-reduce-review-control-plane-to-structured-contracts.md`
- `backlog.d/018-centralize-gate-policy-sources-and-remove-overlap.md`
- `backlog.d/021-domain-tagged-degrade-policy.md`

Any work that touches these areas should either improve them directly or avoid
making them worse.

## References

- `README.md`
- `CONTRIBUTING.md`
- `CLAUDE.md`
- `.spellbook/repo-brief.md`
