# Extract Prompt Library

Priority: medium
Status: ready
Estimate: S

## Goal
Agent prompts are individually testable, discoverable, and modifiable without understanding a 621-line monolith.

## Non-Goals
- Changing prompt content (pure extraction)
- External prompt storage (prompts stay in code)
- Runtime prompt templating engine

## Oracle
- [ ] `lib/thinktank/builtin.ex` contains no `defp *_prompt` functions
- [ ] Prompts live in `lib/thinktank/prompts/` with one module per agent family
- [ ] Each prompt is a module attribute, not a function body
- [ ] Parametric tests verify required template variables (`{{input_text}}`, `{{workspace_root}}`, etc.) are present in each prompt
- [ ] `mix test` passes with no new warnings
- [ ] `builtin.ex` LOC drops below 200

## Notes
Archaeologist found builtin.ex is the largest file (621 LOC) with 23 embedded prompts and zero test coverage. Velocity confirmed it churns frequently during refactors. Extraction makes prompt changes auditable and agent-modifiable. Depends on Theme 1 being in progress or complete for full agent-readiness value.
