package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestEvaluateReadinessFixtures(t *testing.T) {
	if err := evaluateReadinessFixtures(filepath.Join("..", "..", "evals", "readiness-fixtures.json")); err != nil {
		t.Fatalf("evaluate readiness fixtures: %v", err)
	}
}

func TestAssessReadinessAndRouteRemediations(t *testing.T) {
	repo := t.TempDir()
	mustWriteFile(t, filepath.Join(repo, "gradient.yaml"), []byte("name: fixture\n"))
	mustWriteFile(t, filepath.Join(repo, "README.md"), []byte("# Fixture\n"))
	mustWriteFile(t, filepath.Join(repo, ".gradient", "harness", "resolution.json"), []byte(`{"id":"fixture"}`))
	mustWriteFile(t, filepath.Join(repo, "backlog.d", ".keep"), []byte(""))

	report, err := assessReadiness(repo)
	if err != nil {
		t.Fatalf("assess readiness: %v", err)
	}
	if got, want := len(report.Categories), 10; got != want {
		t.Fatalf("categories = %d, want %d", got, want)
	}
	if report.Rubric.RequiredWeight <= report.Rubric.OptionalWeight {
		t.Fatalf("expected required weight > optional weight, got required=%v optional=%v", report.Rubric.RequiredWeight, report.Rubric.OptionalWeight)
	}
	if report.Overall.Score >= 100 {
		t.Fatalf("expected non-perfect score for sparse fixture, got %d", report.Overall.Score)
	}
	if len(report.Remediations) == 0 {
		t.Fatalf("expected remediations for sparse fixture")
	}

	created, err := routeReadinessRemediations(repo, report, time.Date(2026, 5, 18, 17, 5, 0, 0, time.UTC))
	if err != nil {
		t.Fatalf("route readiness remediations: %v", err)
	}
	if len(created) == 0 {
		t.Fatalf("expected routed backlog items")
	}

	body, err := os.ReadFile(created[0])
	if err != nil {
		t.Fatalf("read routed work item: %v", err)
	}
	if !strings.Contains(string(body), "## Readiness Source") {
		t.Fatalf("routed item missing readiness source section: %s", created[0])
	}
}

func mustWriteFile(t *testing.T, path string, body []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", path, err)
	}
	if err := os.WriteFile(path, body, 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}
