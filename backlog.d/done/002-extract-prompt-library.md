# Extract Prompt Library

Priority: medium
Status: done
Estimate: S

## Goal
Agent prompts are individually testable, discoverable, and modifiable without understanding a 621-line monolith.

## Non-Goals
- Changing prompt content (pure extraction)
- External prompt storage (prompts stay in code)
- Runtime prompt templating engine

## Oracle
- [x] `lib/thinktank/builtin.ex` contains no `defp *_prompt` functions
- [x] Prompts live in `lib/thinktank/prompts/` with one module per agent family
- [x] Each prompt is a module attribute, not a function body
- [x] Parametric tests verify required template variables (`{{input_text}}`, `{{workspace_root}}`, etc.) are present in each prompt
- [x] `mix test` passes with no new warnings
- [x] `builtin.ex` LOC drops below 200

## What Was Built
- 3 prompt modules: `Prompts.Research` (5 prompts), `Prompts.Review` (13 prompts), `Prompts.Synthesis` (4 prompts)
- Module attribute pattern: each prompt is a `@attr` with a public accessor, not a function body
- 22 parametric tests covering all template variables and non-empty binary assertions
- `builtin.ex` reduced from 621 to 161 LOC; also refactored agent wiring into data-driven helpers
- `raw_config/0` output verified byte-identical before and after extraction

## Notes
Archaeologist found builtin.ex is the largest file (621 LOC) with 23 embedded prompts and zero test coverage. Velocity confirmed it churns frequently during refactors. Extraction makes prompt changes auditable and agent-modifiable. Depends on Theme 1 being in progress or complete for full agent-readiness value.
