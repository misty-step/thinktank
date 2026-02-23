# Project: thinktank

## Vision
CLI tool that sends a codebase + instructions to multiple LLMs via OpenRouter and synthesizes their responses — turning any AI model into a grounded code reviewer.

**North Star:** The go-to multi-model code analysis tool for engineers who want more than one AI opinion without switching tabs.
**Target User:** Individual engineers and AI-augmented teams who use LLMs for code review, architecture validation, and deep analysis.
**Current Focus:** Model freshness, code quality, and UX polish post-v3.4.0.
**Key Differentiators:** Single-key OpenRouter access to 39+ models; intelligent model selection based on input size; synthesis mode that combines multiple model outputs.

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

## Active Focus

- **Milestone:** Now: Current Sprint — clean maintenance post-v3.4.0
- **Key Issues:** #187, #144, #143, #142 (all P3/later)
- **Theme:** Stability and polish; no active sprint work

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
*Last updated: 2026-02-23*
*Updated during: /groom session*
