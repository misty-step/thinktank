# Project: thinktank

## Vision

Agent-first research tool that gets multiple AI perspectives on a question or problem. Sends context + instructions to multiple LLMs via OpenRouter and synthesizes their responses — turning model diversity into deeper understanding.

**North Star:** The research backbone for AI agents and engineers who need multiple perspectives, not just one model's opinion.
**Target User:** AI agents orchestrating research workflows; engineers who want diverse model perspectives on code, architecture, and design decisions.
**Key Differentiators:** Agent-composable CLI; single-key OpenRouter access to many models; synthesis that extracts signal from model disagreement; context-grounded analysis.

## Principles

- **Agent-first.** Thinktank is a tool for agents to call, not primarily a human-interactive CLI. Design for machine consumption, human readability is a bonus.
- **Perspective diversity is the product.** The value isn't any single model's output — it's the disagreement, convergence, and synthesis across models.
- **Grounded analysis only.** Models always see the actual context — no hallucination-prone "describe your problem" workflows.
- **One key, many minds.** OpenRouter as the single gateway means zero vendor lock-in and instant access to new models as they ship.
- **CLI-native composability.** Pipes, scripts, automation. A building block in larger agent workflows, not an island.
- **Minimal moving parts.** Single binary, single env var, single config file. Complexity in the model layer, simplicity in the tool layer.

## Philosophy

- Model diversity is a research methodology, not a feature. Different models catch different things.
- Synthesis > aggregation. Combining outputs into coherent insight is harder and more valuable than concatenation.
- Resilience over speed. Retry transient failures, degrade gracefully, never lose results.
- Ship what matters. Model registry freshness and output quality outweigh feature count.
- Go idioms: interfaces for testability, table-driven tests, explicit error handling, no globals.

## Domain Glossary

| Term | Definition |
|------|-----------|
| Council | The set of models used in multi-model (synthesis) mode |
| Synthesis | Post-processing step that combines multiple model outputs into one response |
| Orchestrator | `internal/thinktank/orchestrator/` — coordinates parallel model calls |
| ModelProc | `internal/thinktank/modelproc/` — handles a single model's API call lifecycle |
| ConsoleWriter | `internal/logutil/` — dual-output: TUI for humans, structured JSON for machines |
| OpenRouter | Single API gateway used for all model access (one key, unified interface) |
| Dry-run | Preview mode: shows files and token count without making API calls |

## Quality Bar

- [ ] `go test -race ./...` passes (race detection required)
- [ ] `golangci-lint run ./...` clean (zero violations)
- [ ] `./scripts/check-coverage.sh` ≥79% coverage
- [ ] `govulncheck -scan=module` clean (no known vulnerabilities)
- [ ] Conventional commit messages (`feat:`, `fix:`, `docs:`, `chore:`)

## Patterns to Follow

### Dependency Injection for Testability
```go
// Don't use globals. Pass dependencies as interfaces.
type Processor struct {
    apiClient  APIClient
    logger     logutil.LoggerInterface
    console    logutil.ConsoleWriter
}
```

### Table-Driven Tests
```go
tests := []struct {
    name     string
    input    string
    expected string
}{
    {"empty input", "", ""},
    {"normal case", "foo", "bar"},
}
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) { ... })
}
```

### Error Handling
```go
// Never suppress errors with _
// Wrap with context
if err != nil {
    return fmt.Errorf("failed to process model %s: %w", modelID, err)
}
```

## Lessons Learned

| Decision | Outcome | Lesson |
|----------|---------|--------|
| — | — | No retro data yet |

---
*Last updated: 2026-03-14*
*Updated during: /groom session*
