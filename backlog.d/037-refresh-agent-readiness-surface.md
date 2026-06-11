---
acceptance:
    - Cold-agent guidance names ThinkTank's Elixir stack, Pi launcher boundary, global Spellbook harness boundary, and canonical Dagger gate.
    - Repo-local harness settings do not contradict ThinkTank's CI, review, implementation, or backlog workflow.
    - Retired scaffold, Gradient, and historical Go/router language is clearly marked historical or removed from active instructions.
evidence_required:
    - AGENTS.md review
    - agent_config/AGENTS.md review
    - .codex/config.toml review
    - .pi/settings.json review
    - mix test
id: 037-refresh-agent-readiness-surface
lifecycle_stage: Harness
status: ready
title: Refresh Agent Readiness Surface
---

# Refresh Agent Readiness Surface

Priority: medium
Status: ready
Estimate: S

## Goal

A cold agent can discover ThinkTank's current Elixir/Pi launcher boundary,
canonical gate, backlog lifecycle, and repo-owned harness surfaces without
depending on retired scaffold state or duplicate ticket IDs.

## Oracle

- [ ] `AGENTS.md`, `CLAUDE.md`, `README.md`, `project.md`, `agent_config/AGENTS.md`, `.codex/config.toml`, and `.pi/settings.json` agree on the thin launcher boundary and `./scripts/with-colima.sh dagger call check`.
- [ ] Active guidance points to `backlog.d/` and the current Elixir modules, not historical Go/router/Gradient surfaces except as marked history.
- [ ] The active backlog no longer reuses the numeric ID of `backlog.d/done/002-extract-prompt-library.md`.
- [ ] `mix test` passes after the guidance cleanup.

## Notes

- Historical generated guidance missed Elixir, `mix.exs`, `mix.lock`, Dagger,
  and the active global Spellbook harness boundary.
- The readiness surface should describe ThinkTank's Elixir CLI, Pi launcher
  boundary, artifact contracts, and Dagger gate directly.
- `/groom` renumbered this item from active `002` to `037` because `002` was
  already used under `backlog.d/done/`.

## Repo Anchors

- `AGENTS.md`
- `README.md`
- `project.md`
- `agent_config/AGENTS.md`
- `agent_config/settings.json`
