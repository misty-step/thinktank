---
name: zero-tech-debt
description: |
  Rework a change as if the intended UX and architecture existed from day one,
  deleting compatibility cruft and accidental complexity. Trigger:
  /zero-tech-debt.
user-invocable: true
argument-hint: "[--scope <path>] [--report-only] [--apply]"
---

# Zero Tech Debt

Use this when a patch preserves old modes, wrappers, aliases, flags, or
fallbacks only because they already existed. The goal is the intended end
state, not the smallest diff from the historical path.

## Decision

This primitive belongs in Gradient's repo-local harness first because Gradient
needs it immediately for self-maintenance. It should be upstreamed into
Spellbook once a few real Gradient cycles prove the wording and gates are
portable across repositories.

## Steps

1. State the intended end state in one or two sentences.

2. Search for real callers before preserving compatibility. If a mode, prop,
   wrapper, route alias, fallback, or command path has no current caller,
   delete it.

3. Reshape around the final product surface. Prefer one clear component or flow
   over mode flags. Split only when it creates an obvious boundary such as
   state, layout, controls, or domain commands.

4. Move shared rules to one place. Feature flags, permissions, route gating,
   URL state, and command naming should not be duplicated across pages or
   hidden in view components.

5. Verify the intended flow and any deleted assumptions that affect navigation,
   permissions, persisted state, or public contracts.

## Rules

- Optimize for the code that should exist, not the smallest diff from the old
  shape.
- Delete dead compatibility paths instead of making them better.
- Do not invent a generic framework for one feature.
- Keep the refactor scoped to what makes the final shape coherent.
- Prefer names that describe product intent over implementation history.

## Gradient Gate

For Gradient itself, run:

```sh
./scripts/gradient.sh validate
./scripts/gradient.sh eval
```

The evidence packet should name what compatibility path was deleted or why it
was kept because a real caller still exists.
