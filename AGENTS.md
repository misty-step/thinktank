# AGENTS.md

Map, not manual.

## What ThinkTank Is

ThinkTank is a thin Pi bench launcher for research and review.

- Agents are configured in code or YAML
- Benches are named sets of agents
- ThinkTank launches Pi, captures raw outputs, and records artifacts

## What ThinkTank Is Not

- Not a semantic workflow engine
- Not a stage graph DSL
- Not a prose parser
- Not a second direct-API path that bypasses Pi

## Architecture

- `lib/thinktank/cli.ex` — CLI surface
- `lib/thinktank/engine.ex` — bench resolution and launch
- `lib/thinktank/builtin.ex` — built-in agents and benches
- `lib/thinktank/executor/agentic.ex` — Pi subprocess runner
- `lib/thinktank/run_store.ex` — manifests and artifacts

## Doctrine

- Workspace is context
- Launch, sandbox, timeout, and record in Elixir
- Explore and reason in Pi
- Prefer general tools over bespoke harness logic
- Prefer deletion over additional orchestration layers

## Local Gates

- Use `./scripts/with-colima.sh dagger call check` as the canonical local merge-readiness gate.
- `./scripts/with-colima.sh dagger call check` now enforces formatting, compile warnings, `credo --strict`, Dialyzer, shell/YAML hygiene, gitleaks, the repo-owned security gate, live model-ID validation, the architecture gate, escript smoke, and an `87%` coverage floor.
- Use `mix test` and `mix compile --warnings-as-errors` as targeted fallback or debugging gates when you need a host-native Elixir check.
- Native Git hooks live in `.githooks/` and are installed by `./scripts/setup.sh`.

## Smell Tests

- Regex over agent prose: wrong layer
- Semantic phases and handoffs: probably wrong layer
- Precomputed review bundles: probably wrong layer
- Extra prompt prose to compensate for weak models: probably wrong layer

## Shared Skills

Agent-agnostic skills live under `.agent/skills/` and are readable by both
Claude Code and Codex. Follow a skill's `SKILL.md` when its trigger matches.

- `.agent/skills/model-research/` — monthly OpenRouter-focused model scan
  with Thinktank-fit recommendations. Trigger: "latest models",
  "model research", "should we swap X", unfamiliar model names.

## Claude Code Harness

Claude-specific skills and agents live under `.claude/`. Installed via
`/tailor`. Slash commands map to `.claude/skills/<name>/SKILL.md`;
named subagents to `.claude/agents/<name>.md`.

Repo-local agent files under `.claude/agents/*.md` define lenses only.
They must not hardcode model IDs, model families, or reasoning tiers; the
caller/runtime chooses the model.

Workflow skills that touch the gate have repo-specialized notes under
their `references/` directory. The load-bearing command everywhere is:

```
./scripts/with-colima.sh dagger call check
```

See the following per-skill notes for concrete, this-repo-only guidance:

- `.claude/skills/ci/references/thinktank-gate.md`
- `.claude/skills/deliver/references/thinktank-gate.md`
- `.claude/skills/settle/references/thinktank-settle.md`
- `.claude/skills/yeet/references/thinktank-yeet.md`
- `.claude/skills/deps/references/thinktank-deps.md`

Tailored (repo-specific) skills already present:

- `.claude/skills/demo/` — CLI-focused demo capture for thinktank
- `.claude/skills/qa/` — CLI behavior verifier (not browser QA)
- `.claude/skills/model-research/` → symlink to `.agent/skills/model-research/`

Universal and workflow skills installed from spellbook:

- Universal: research, groom, reflect, shape, diagnose
- Workflow: ci, deliver, implement, refactor, settle, yeet, deps,
  flywheel, code-review

Agents installed (philosophy bench + build roles): beck, builder,
carmack, critic, grug, ousterhout, planner.

Permissions allowlist lives at `.claude/settings.local.json` and is
**git-ignored** — not shared between clones. It denies `--no-verify` and
force-push by default, consistent with this repo's red-line that the
Dagger gate is load-bearing.

## References

- `README.md`
- `CLAUDE.md`
