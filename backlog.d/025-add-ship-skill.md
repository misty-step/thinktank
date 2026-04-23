# Add Ship Skill

Priority: low
Status: in-progress
Estimate: S

## Goal
ThinkTank can use a repo-local `ship` skill for final-mile branch landing without depending on spellbook-global files that do not exist in this repo.

## Non-Goals
- Replacing `/settle` or `/yeet`
- Adding new shell helper libraries under `scripts/lib/`
- Changing release-please or merge policy

## Constraints / Invariants
- The installed skill lives in `.agent/skills/ship/` and is bridged into `.claude/skills/`, `.codex/skills/`, and `.pi/skills/`
- The skill body must match ThinkTank's actual conventions: `backlog.d/done/`, `master`, and `reflect/<cycle-id>`
- The install must not rely on missing repo-local helpers such as `scripts/lib/backlog.sh` or `scripts/lib/verdicts.sh`

## Repo Anchors
- `.agent/skills/`
- `.claude/skills/`
- `.codex/skills/`
- `.pi/skills/`
- `AGENTS.md`

## Oracle
- [x] `.agent/skills/ship/SKILL.md` exists with ThinkTank-specific guidance
- [x] `.claude/skills/ship`, `.codex/skills/ship`, and `.pi/skills/ship` resolve to the shared skill
- [x] `AGENTS.md` lists `ship` in the skill index
- [x] `scripts/ci/harness-agent-gate.sh` passes after the install

## Notes
Spellbook already has a global `ship` skill, but the upstream body assumes backlog helper scripts and archive paths that this repo does not use. The repo-local install should preserve the intent while adapting the operational details to ThinkTank.
