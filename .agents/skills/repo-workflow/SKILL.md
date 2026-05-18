---
name: repo-workflow
description: Use this repository's Gradient-detected workflow, docs, and verification commands.
user-invocable: true
---

# Repo Workflow

Repository: thinktank

## Read First

- `README.md`
- `AGENTS.md`
- `CLAUDE.md`
- `docs`

## Verify With

- `gradient validate`

## Rules

- Prefer repository docs and detected commands over generic assumptions.
- Run `gradient resolve` and `gradient validate` before closing Gradient-managed work.
- Log product or readiness improvements as work items instead of silently changing product code during initialization.
