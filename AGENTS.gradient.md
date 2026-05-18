# Gradient Harness For ThinkTank

This repository is Gradient-managed at adoption level 'evidence' with profile 'solo-frontier'.

## Repo Signals

- Repository: 'thinktank'
- Languages: Elixir
- Package manifests: mix.exs, mix.lock
- Docs: README.md, AGENTS.md, CLAUDE.md, docs
- CI/automation: .github/workflows, ci/, dagger.json, scripts/with-colima.sh
- Existing harness truth: AGENTS.md, .agent/skills, .claude/skills, .codex/skills, .pi/skills

## Agent Workflow

1. Start by running 'gradient resolve' and 'gradient validate'.
2. Read AGENTS.md, README.md, CONTRIBUTING.md, CLAUDE.md, and the relevant
   `.agent/skills/*/SKILL.md` before changing product code.
3. Treat ThinkTank as a thin Pi-backed bench launcher, not a semantic workflow
   engine. Keep workspace, launch, sandbox, timeout, artifact, and record
   ownership in Elixir.
4. Use the detected verification commands when they apply:

- `gradient validate`
- `./scripts/with-colima.sh dagger call check`

## Gradient Contract

Gradient owns the repo-local harness projection and profile. Existing product
code is repo-owned; initialization logs improvement work instead of silently
editing product implementation.

ThinkTank's pre-existing `.agent/skills` tree is the repo-tailored skill
authority. Gradient-native skills under `.agents/skills` add Gradient lifecycle
commands and should not override ThinkTank-specific gate, review, QA, demo, or
implementation guidance.
