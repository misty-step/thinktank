package main

import (
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	readinessRequiredWeight = 0.7
	readinessOptionalWeight = 0.3
)

var errReadinessFound = errors.New("readiness-match-found")

type readinessReport struct {
	Schema       string                 `json:"$schema"`
	ID           string                 `json:"id"`
	GeneratedAt  string                 `json:"generated_at"`
	RepoRoot     string                 `json:"repo_root"`
	Rubric       readinessRubric        `json:"rubric"`
	Overall      readinessOverall       `json:"overall"`
	Categories   []readinessCategory    `json:"categories"`
	Remediations []readinessRemediation `json:"remediations"`
}

type readinessRubric struct {
	Version        string  `json:"version"`
	RequiredWeight float64 `json:"required_weight"`
	OptionalWeight float64 `json:"optional_weight"`
	Reference      string  `json:"reference"`
}

type readinessOverall struct {
	Score int    `json:"score"`
	Tier  string `json:"tier"`
}

type readinessCategory struct {
	ID       string           `json:"id"`
	Title    string           `json:"title"`
	Score    int              `json:"score"`
	MaxScore int              `json:"max_score"`
	Required readinessBucket  `json:"required"`
	Optional readinessBucket  `json:"optional"`
	Checks   []readinessCheck `json:"checks"`
}

type readinessBucket struct {
	Passed int `json:"passed"`
	Total  int `json:"total"`
}

type readinessCheck struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	Required    bool     `json:"required"`
	Passed      bool     `json:"passed"`
	Detail      string   `json:"detail"`
	Evidence    []string `json:"evidence"`
	Remediation string   `json:"remediation"`
}

type readinessRemediation struct {
	ID                string   `json:"id"`
	Category          string   `json:"category"`
	Priority          string   `json:"priority"`
	Summary           string   `json:"summary"`
	Rationale         string   `json:"rationale"`
	SuggestedEvidence []string `json:"suggested_evidence"`
}

type readinessCategorySpec struct {
	ID     string
	Title  string
	Checks []readinessCheckSpec
}

type readinessCheckSpec struct {
	ID          string
	Title       string
	Required    bool
	Remediation string
	Evidence    []string
	Detect      func(repo string) (passed bool, detail string, evidence []string)
}

type readinessFixture struct {
	Cases []readinessFixtureCase `json:"cases"`
}

type readinessFixtureCase struct {
	Name       string                     `json:"name"`
	Categories []readinessFixtureCategory `json:"categories"`
	Expected   readinessFixtureExpected   `json:"expected"`
}

type readinessFixtureCategory struct {
	ID       string          `json:"id"`
	Required readinessBucket `json:"required"`
	Optional readinessBucket `json:"optional"`
}

type readinessFixtureExpected struct {
	MinScore int    `json:"min_score"`
	MaxScore int    `json:"max_score"`
	Tier     string `json:"tier"`
}

func cmdReadiness(args []string) error {
	routeBacklog := false
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--route=backlog":
			routeBacklog = true
		case "--route":
			if i+1 >= len(args) || args[i+1] != "backlog" {
				return errors.New("usage: gradient readiness [--route backlog]")
			}
			routeBacklog = true
			i++
		default:
			return errors.New("usage: gradient readiness [--route backlog]")
		}
	}

	report, err := assessReadiness(root)
	if err != nil {
		return err
	}
	mdPath, jsonPath, err := writeReadinessReport(root, report)
	if err != nil {
		return err
	}
	fmt.Print(renderReadinessMarkdown(report))
	fmt.Printf("\nreport markdown: %s\n", rel(mdPath))
	fmt.Printf("report json: %s\n", rel(jsonPath))

	if routeBacklog {
		created, err := routeReadinessRemediations(root, report, time.Now().UTC())
		if err != nil {
			return err
		}
		if len(created) == 0 {
			fmt.Println("no remediation work items created")
		} else {
			fmt.Println("routed remediation work:")
			for _, path := range created {
				fmt.Println("- " + rel(path))
			}
		}
	}
	return nil
}

func assessReadiness(repo string) (readinessReport, error) {
	specs := readinessCategorySpecs()
	categories := make([]readinessCategory, 0, len(specs))
	remediations := make([]readinessRemediation, 0)

	for _, spec := range specs {
		category := readinessCategory{ID: spec.ID, Title: spec.Title, MaxScore: 10}
		for _, check := range spec.Checks {
			passed, detail, evidence := check.Detect(repo)
			result := readinessCheck{
				ID:          check.ID,
				Title:       check.Title,
				Required:    check.Required,
				Passed:      passed,
				Detail:      detail,
				Evidence:    evidence,
				Remediation: check.Remediation,
			}
			category.Checks = append(category.Checks, result)
			if check.Required {
				category.Required.Total++
				if passed {
					category.Required.Passed++
				}
			} else {
				category.Optional.Total++
				if passed {
					category.Optional.Passed++
				}
			}
			if !passed {
				priority := "medium"
				if check.Required {
					priority = "high"
				}
				remediations = append(remediations, readinessRemediation{
					ID:                spec.ID + "-" + check.ID,
					Category:          spec.ID,
					Priority:          priority,
					Summary:           spec.Title + ": " + check.Title,
					Rationale:         detail,
					SuggestedEvidence: suggestedReadinessEvidence(check),
				})
			}
		}
		category.Score = scoreReadinessCategory(category.Required, category.Optional)
		categories = append(categories, category)
	}

	sum := 0
	for _, category := range categories {
		sum += category.Score
	}
	overall := 0
	if len(categories) > 0 {
		overall = int(math.Round((float64(sum) / float64(len(categories))) * 10))
	}
	report := readinessReport{
		Schema:      "../../schemas/readiness-report.schema.json",
		ID:          "readiness-" + stamp(),
		GeneratedAt: now(),
		RepoRoot:    ".",
		Rubric: readinessRubric{
			Version:        "readiness-v1",
			RequiredWeight: readinessRequiredWeight,
			OptionalWeight: readinessOptionalWeight,
			Reference:      "docs/evals.md#readiness-rubric",
		},
		Overall: readinessOverall{
			Score: overall,
			Tier:  readinessTier(overall),
		},
		Categories:   categories,
		Remediations: remediations,
	}
	return report, nil
}

func suggestedReadinessEvidence(check readinessCheckSpec) []string {
	if len(check.Evidence) > 0 {
		return append([]string{}, check.Evidence...)
	}
	return []string{check.Remediation}
}

func readinessTier(score int) string {
	switch {
	case score >= 85:
		return "high"
	case score >= 70:
		return "strong"
	case score >= 50:
		return "functional"
	default:
		return "low"
	}
}

func scoreReadinessCategory(required, optional readinessBucket) int {
	reqRatio := ratio(required.Passed, required.Total)
	optRatio := ratio(optional.Passed, optional.Total)
	score := int(math.Round((reqRatio*readinessRequiredWeight + optRatio*readinessOptionalWeight) * 10))
	if score < 0 {
		return 0
	}
	if score > 10 {
		return 10
	}
	return score
}

func ratio(passed, total int) float64 {
	if total <= 0 {
		return 1
	}
	return float64(passed) / float64(total)
}

func writeReadinessReport(repo string, report readinessReport) (string, string, error) {
	base := filepath.Join(repo, ".gradient", "readiness", report.ID)
	jsonPath := base + ".json"
	mdPath := base + ".md"
	if err := writeJSON(jsonPath, report); err != nil {
		return "", "", err
	}
	if err := os.WriteFile(mdPath, []byte(renderReadinessMarkdown(report)), 0o644); err != nil {
		return "", "", err
	}
	return mdPath, jsonPath, nil
}

func renderReadinessMarkdown(report readinessReport) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# Gradient Agent-Readiness Report\n\n")
	fmt.Fprintf(&b, "id: %s\n", report.ID)
	fmt.Fprintf(&b, "generated_at: %s\n", report.GeneratedAt)
	fmt.Fprintf(&b, "overall_score: %d/100\n", report.Overall.Score)
	fmt.Fprintf(&b, "readiness_tier: %s\n\n", report.Overall.Tier)
	fmt.Fprintf(&b, "Rubric: %s (required basics %.0f%%, optional maturity %.0f%%).\n\n", report.Rubric.Version, report.Rubric.RequiredWeight*100, report.Rubric.OptionalWeight*100)
	fmt.Fprintf(&b, "Reference: %s\n\n", report.Rubric.Reference)
	fmt.Fprintf(&b, "## Category Scores\n\n")
	fmt.Fprintf(&b, "| Category | Score | Required | Optional |\n")
	fmt.Fprintf(&b, "| --- | --- | --- | --- |\n")
	for _, category := range report.Categories {
		fmt.Fprintf(&b, "| %s | %d/%d | %d/%d | %d/%d |\n", category.ID, category.Score, category.MaxScore, category.Required.Passed, category.Required.Total, category.Optional.Passed, category.Optional.Total)
	}
	fmt.Fprintf(&b, "\n## Remediation Items\n\n")
	if len(report.Remediations) == 0 {
		fmt.Fprintf(&b, "- none\n")
		return b.String()
	}
	for _, remediation := range report.Remediations {
		fmt.Fprintf(&b, "- [%s] %s\n", remediation.Priority, remediation.Summary)
	}
	return b.String()
}

func routeReadinessRemediations(repo string, report readinessReport, generatedAt time.Time) ([]string, error) {
	if len(report.Remediations) == 0 {
		return nil, nil
	}
	if err := os.MkdirAll(filepath.Join(repo, "backlog.d"), 0o755); err != nil {
		return nil, err
	}
	next := nextWorkNumberForRepo(repo)
	created := make([]string, 0, len(report.Remediations))
	for _, remediation := range report.Remediations {
		id := fmt.Sprintf("%03d-%s", next, slug("readiness-"+remediation.ID))
		path := filepath.Join(repo, "backlog.d", id+".md")
		fm := anymap{
			"id":              id,
			"title":           "Readiness remediation: " + remediation.Summary,
			"status":          "ready",
			"lifecycle_stage": "Policy/Eval",
			"acceptance": []string{
				"Repository readiness gap is remediated and rerun through `gradient readiness`.",
			},
			"evidence_required": []string{
				"gradient readiness",
				"gradient validate",
			},
		}
		body := "## Readiness Source\n\n" +
			"- report_id: " + report.ID + "\n" +
			"- generated_at: " + generatedAt.UTC().Format(time.RFC3339) + "\n" +
			"- category: " + remediation.Category + "\n" +
			"- priority: " + remediation.Priority + "\n\n" +
			"## Gap\n\n" + remediation.Rationale + "\n\n" +
			"## Suggested Evidence\n\n"
		if len(remediation.SuggestedEvidence) == 0 {
			body += "- gradient readiness\n"
		} else {
			for _, evidence := range remediation.SuggestedEvidence {
				body += "- " + evidence + "\n"
			}
		}
		if err := writeDoc(path, fm, body); err != nil {
			return nil, err
		}
		created = append(created, path)
		next++
	}
	return created, nil
}

func nextWorkNumberForRepo(repo string) int {
	max := 0
	re := regexp.MustCompile(`^([0-9]{3})-`)
	patterns := []string{
		filepath.Join(repo, "backlog.d", "[0-9][0-9][0-9]-*.md"),
		filepath.Join(repo, "backlog.d", "_done", "[0-9][0-9][0-9]-*.md"),
	}
	for _, pattern := range patterns {
		matches, _ := filepath.Glob(pattern)
		for _, path := range matches {
			if m := re.FindStringSubmatch(filepath.Base(path)); len(m) == 2 {
				var n int
				fmt.Sscanf(m[1], "%d", &n)
				if n > max {
					max = n
				}
			}
		}
	}
	return max + 1
}

func evaluateReadinessFixtures(path string) error {
	var fixtures readinessFixture
	if err := readJSON(path, &fixtures); err != nil {
		return err
	}
	if len(fixtures.Cases) == 0 {
		return fmt.Errorf("%s has no readiness cases", path)
	}
	hasLow, hasHigh := false, false
	for _, c := range fixtures.Cases {
		if len(c.Categories) == 0 {
			return fmt.Errorf("%s case %s missing categories", path, c.Name)
		}
		sum := 0
		for _, category := range c.Categories {
			sum += scoreReadinessCategory(category.Required, category.Optional)
		}
		score := int(math.Round((float64(sum) / float64(len(c.Categories))) * 10))
		tier := readinessTier(score)
		if score < c.Expected.MinScore || score > c.Expected.MaxScore {
			return fmt.Errorf("%s case %s score %d outside [%d,%d]", path, c.Name, score, c.Expected.MinScore, c.Expected.MaxScore)
		}
		if c.Expected.Tier != "" && tier != c.Expected.Tier {
			return fmt.Errorf("%s case %s tier %s != expected %s", path, c.Name, tier, c.Expected.Tier)
		}
		if tier == "low" {
			hasLow = true
		}
		if tier == "high" {
			hasHigh = true
		}
	}
	if !hasLow || !hasHigh {
		return fmt.Errorf("%s must include at least one low and one high readiness case", path)
	}
	return nil
}

func readinessCategorySpecs() []readinessCategorySpec {
	return []readinessCategorySpec{
		{
			ID:    "setup",
			Title: "Setup Automation",
			Checks: []readinessCheckSpec{
				{
					ID:          "profile",
					Title:       "Repository has a Gradient profile.",
					Required:    true,
					Remediation: "Commit `gradient.yaml` so setup can be reproduced.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{"gradient.yaml"}, "found gradient profile", "missing gradient.yaml")
					},
				},
				{
					ID:          "entrypoint",
					Title:       "Gradient command entrypoint exists.",
					Required:    true,
					Remediation: "Add a checked-in command wrapper such as `scripts/gradient.sh`.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAnyPaths(repo, []string{"scripts/gradient.sh", "cmd/gradient/main.go"}, "found command entrypoint", "missing gradient command entrypoint")
					},
				},
				{
					ID:          "lockfile",
					Title:       "Dependency lockfile exists.",
					Required:    false,
					Remediation: "Add a lockfile (`go.sum`, `pnpm-lock.yaml`, etc.) for reproducible setup.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAnyPaths(repo, []string{"go.sum", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "poetry.lock", "Pipfile.lock", "Cargo.lock"}, "found dependency lockfile", "missing dependency lockfile")
					},
				},
				{
					ID:          "bootstrap-script",
					Title:       "Repository includes setup/bootstrap automation.",
					Required:    false,
					Remediation: "Add a setup script or dev environment definition for new operators.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAnyPaths(repo, []string{"scripts/init-workspace.sh", ".devcontainer/devcontainer.json", "mise.toml", ".tool-versions", "Dockerfile"}, "found setup automation", "missing setup automation file")
					},
				},
			},
		},
		{
			ID:    "tests",
			Title: "Tests And Quality Gates",
			Checks: []readinessCheckSpec{
				{
					ID:          "test-artifacts",
					Title:       "Repository includes executable test artifacts.",
					Required:    true,
					Remediation: "Add regression tests (`*_test.go`, `*.spec.*`, or `scripts/test-*.sh`).",
					Detect: func(repo string) (bool, string, []string) {
						paths := findTestArtifacts(repo)
						if len(paths) == 0 {
							return false, "no test artifacts found", nil
						}
						return true, "found test artifacts", paths
					},
				},
				{
					ID:          "test-command",
					Title:       "Repository has a test or validation command.",
					Required:    true,
					Remediation: "Add a documented test command (`go test`, `scripts/validate.sh`, or equivalent).",
					Detect: func(repo string) (bool, string, []string) {
						paths := findExistingPaths(repo, []string{"scripts/validate.sh", "scripts/eval-gradient.sh", "Makefile"})
						if len(paths) == 0 {
							return false, "missing test/validation command wrapper", nil
						}
						return true, "found test/validation command wrapper", paths
					},
				},
				{
					ID:          "regression-suite",
					Title:       "Repository has regression scripts.",
					Required:    false,
					Remediation: "Add repeatable regression scripts (for example `scripts/test-*.sh`).",
					Detect: func(repo string) (bool, string, []string) {
						paths := globRel(repo, "scripts/test-*.sh")
						if len(paths) == 0 {
							return false, "missing regression scripts", nil
						}
						return true, "found regression scripts", paths
					},
				},
				{
					ID:          "coverage-signal",
					Title:       "Repository records test coverage or gate output.",
					Required:    false,
					Remediation: "Capture coverage output or publish explicit gate artifacts.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAnyPaths(repo, []string{"coverage.out", ".github/workflows/ci.yml"}, "found coverage/gate signal", "missing coverage/gate signal")
					},
				},
			},
		},
		{
			ID:    "ci",
			Title: "CI And Automation",
			Checks: []readinessCheckSpec{
				{
					ID:          "workflow",
					Title:       "Repository includes CI workflow definitions.",
					Required:    true,
					Remediation: "Add CI workflows under `.github/workflows/`.",
					Detect: func(repo string) (bool, string, []string) {
						paths := append(globRel(repo, ".github/workflows/*.yml"), globRel(repo, ".github/workflows/*.yaml")...)
						if len(paths) == 0 {
							return false, "missing CI workflow files", nil
						}
						return true, "found CI workflow files", paths
					},
				},
				{
					ID:          "ci-gate",
					Title:       "CI executes tests or validation.",
					Required:    true,
					Remediation: "Run `go test` or `gradient validate` inside CI workflows.",
					Detect: func(repo string) (bool, string, []string) {
						paths := append(globAbs(repo, ".github/workflows/*.yml"), globAbs(repo, ".github/workflows/*.yaml")...)
						for _, path := range paths {
							b, err := os.ReadFile(path)
							if err != nil {
								continue
							}
							text := strings.ToLower(string(b))
							if strings.Contains(text, "go test") || strings.Contains(text, "gradient validate") || strings.Contains(text, "./scripts/validate.sh") {
								return true, "found CI validation command", []string{toRepoRel(repo, path)}
							}
						}
						return false, "CI workflows do not show test/validation commands", nil
					},
				},
				{
					ID:          "pre-commit",
					Title:       "Repository has local pre-commit automation.",
					Required:    false,
					Remediation: "Add pre-commit or lefthook automation to shift checks left.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAnyPaths(repo, []string{".pre-commit-config.yaml", "lefthook.yml", "lefthook.yaml"}, "found pre-commit automation", "missing pre-commit automation")
					},
				},
				{
					ID:          "ci-badge",
					Title:       "README exposes CI signal.",
					Required:    false,
					Remediation: "Publish CI status in README for onboarding clarity.",
					Detect: func(repo string) (bool, string, []string) {
						path := filepath.Join(repo, "README.md")
						b, err := os.ReadFile(path)
						if err != nil {
							return false, "missing README CI signal", nil
						}
						text := strings.ToLower(string(b))
						if strings.Contains(text, "badge") && strings.Contains(text, "ci") {
							return true, "found README CI signal", []string{"README.md"}
						}
						return false, "README does not show CI signal", nil
					},
				},
			},
		},
		{
			ID:    "docs",
			Title: "Documentation",
			Checks: []readinessCheckSpec{
				{
					ID:          "readme",
					Title:       "Repository has a README.",
					Required:    true,
					Remediation: "Add or restore `README.md` with setup and workflow context.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{"README.md"}, "found README", "missing README")
					},
				},
				{
					ID:          "operators-guide",
					Title:       "Repository has operator guidance (`AGENTS.md`).",
					Required:    true,
					Remediation: "Add `AGENTS.md` with public-safe boundaries and repo workflow.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{"AGENTS.md"}, "found operator guidance", "missing AGENTS.md")
					},
				},
				{
					ID:          "architecture",
					Title:       "Architecture and module contracts docs exist.",
					Required:    false,
					Remediation: "Document architecture and module contracts for agent boundaries.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{"docs/architecture.md", "docs/module-contracts.md"}, "found architecture docs", "missing architecture/module contracts docs")
					},
				},
				{
					ID:          "onboarding",
					Title:       "Onboarding guidance exists.",
					Required:    false,
					Remediation: "Add onboarding guidance (`docs/onboarding-playbook.md` or `CONTRIBUTING.md`).",
					Detect: func(repo string) (bool, string, []string) {
						return checkAnyPaths(repo, []string{"docs/onboarding-playbook.md", "CONTRIBUTING.md"}, "found onboarding guidance", "missing onboarding guidance")
					},
				},
			},
		},
		{
			ID:    "harness",
			Title: "Harness Quality",
			Checks: []readinessCheckSpec{
				{
					ID:          "resolution",
					Title:       "Harness resolution artifact exists.",
					Required:    true,
					Remediation: "Run `gradient resolve` and commit `.gradient/harness/resolution.json`.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{".gradient/harness/resolution.json"}, "found harness resolution", "missing harness resolution")
					},
				},
				{
					ID:          "skills",
					Title:       "Shared skill definitions exist.",
					Required:    true,
					Remediation: "Add shared skills under `.agents/skills/*/SKILL.md`.",
					Detect: func(repo string) (bool, string, []string) {
						paths := globRel(repo, ".agents/skills/*/SKILL.md")
						if len(paths) == 0 {
							return false, "missing shared skill definitions", nil
						}
						return true, "found shared skill definitions", paths
					},
				},
				{
					ID:          "agents",
					Title:       "Agent definitions exist.",
					Required:    false,
					Remediation: "Add focused agents under `.agents/agents/*.md`.",
					Detect: func(repo string) (bool, string, []string) {
						paths := globRel(repo, ".agents/agents/*.md")
						if len(paths) == 0 {
							return false, "missing agent definitions", nil
						}
						return true, "found agent definitions", paths
					},
				},
				{
					ID:          "bridges",
					Title:       "Harness bridge directories exist.",
					Required:    false,
					Remediation: "Add harness bridge directories (`.claude`, `.codex`, `.pi`) when relevant.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAnyPaths(repo, []string{".claude/skills", ".codex/skills", ".pi/skills"}, "found harness bridge directory", "missing harness bridge directories")
					},
				},
			},
		},
		{
			ID:    "work",
			Title: "Work Tracking",
			Checks: []readinessCheckSpec{
				{
					ID:          "backlog",
					Title:       "Repository has numbered backlog work items.",
					Required:    true,
					Remediation: "Add numbered work items under `backlog.d/`.",
					Detect: func(repo string) (bool, string, []string) {
						paths := globRel(repo, "backlog.d/[0-9][0-9][0-9]-*.md")
						if len(paths) == 0 {
							return false, "missing numbered backlog work items", nil
						}
						return true, "found numbered backlog work items", paths
					},
				},
				{
					ID:          "contracts",
					Title:       "Work items include acceptance and evidence fields.",
					Required:    true,
					Remediation: "Adopt Gradient frontmatter with `acceptance` and `evidence_required`.",
					Detect: func(repo string) (bool, string, []string) {
						paths := globRel(repo, "backlog.d/[0-9][0-9][0-9]-*.md")
						for _, relPath := range paths {
							fm, _, err := splitDoc(filepath.Join(repo, relPath))
							if err != nil {
								continue
							}
							if len(stringSlice(fm["acceptance"])) > 0 && len(stringSlice(fm["evidence_required"])) > 0 {
								return true, "found work item contract fields", []string{relPath}
							}
						}
						return false, "no active work item has acceptance/evidence fields", nil
					},
				},
				{
					ID:          "done-lane",
					Title:       "Repository has a closed-work lane.",
					Required:    false,
					Remediation: "Add `backlog.d/_done/` to preserve lifecycle history.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{"backlog.d/_done"}, "found done lane", "missing done lane")
					},
				},
				{
					ID:          "feedback-route",
					Title:       "Repository has feedback routing artifacts.",
					Required:    false,
					Remediation: "Capture feedback records under `.gradient/feedback/` and route high-value items to backlog.",
					Detect: func(repo string) (bool, string, []string) {
						paths := globRel(repo, ".gradient/feedback/*.json")
						if len(paths) == 0 {
							return false, "missing feedback artifacts", nil
						}
						return true, "found feedback artifacts", paths
					},
				},
			},
		},
		{
			ID:    "security",
			Title: "Security Hygiene",
			Checks: []readinessCheckSpec{
				{
					ID:          "gitignore",
					Title:       "Repository has `.gitignore` hygiene controls.",
					Required:    true,
					Remediation: "Add `.gitignore` entries for local secrets and transient artifacts.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{".gitignore"}, "found .gitignore", "missing .gitignore")
					},
				},
				{
					ID:          "public-safe-doc",
					Title:       "Repository documents public-safe boundaries.",
					Required:    true,
					Remediation: "Document public-safe boundaries in `AGENTS.md` or companion docs.",
					Detect: func(repo string) (bool, string, []string) {
						for _, relPath := range []string{"AGENTS.md", "docs/gradient-machine-brief.md", "docs/ownership.md"} {
							path := filepath.Join(repo, relPath)
							b, err := os.ReadFile(path)
							if err != nil {
								continue
							}
							if strings.Contains(strings.ToLower(string(b)), "public-safe") {
								return true, "found public-safe boundary guidance", []string{relPath}
							}
						}
						return false, "missing explicit public-safe boundary guidance", nil
					},
				},
				{
					ID:          "security-fixture",
					Title:       "Repository includes synthetic secret-hygiene fixtures.",
					Required:    false,
					Remediation: "Add synthetic secret-hygiene fixtures (`evals/security-fixtures.json`).",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{"evals/security-fixtures.json"}, "found security fixtures", "missing security fixtures")
					},
				},
				{
					ID:          "secret-scan-automation",
					Title:       "Repository automation references secret scanning.",
					Required:    false,
					Remediation: "Add secret scan automation (for example gitleaks in CI).",
					Detect: func(repo string) (bool, string, []string) {
						paths := append(globAbs(repo, ".github/workflows/*.yml"), globAbs(repo, ".github/workflows/*.yaml")...)
						for _, path := range paths {
							b, err := os.ReadFile(path)
							if err != nil {
								continue
							}
							text := strings.ToLower(string(b))
							if strings.Contains(text, "gitleaks") || strings.Contains(text, "secret") {
								return true, "found secret scanning signal in CI", []string{toRepoRel(repo, path)}
							}
						}
						return false, "missing secret scanning automation signal", nil
					},
				},
			},
		},
		{
			ID:    "observability",
			Title: "Observability And Debugging",
			Checks: []readinessCheckSpec{
				{
					ID:          "runbook",
					Title:       "Repository documents debugging or operations workflow.",
					Required:    true,
					Remediation: "Add a runbook or debugging section that names logs, metrics, traces, and failure triage steps.",
					Evidence:    []string{"README.md or docs/runbook.md with debugging, logs, metrics, or tracing guidance"},
					Detect: func(repo string) (bool, string, []string) {
						paths := docsContaining(repo, []string{"debug", "runbook", "logs", "metrics", "tracing", "observability"})
						if len(paths) == 0 {
							return false, "missing debugging or observability guidance", nil
						}
						return true, "found debugging or observability guidance", paths
					},
				},
				{
					ID:          "runtime-signals",
					Title:       "Repository exposes runtime signal hooks.",
					Required:    false,
					Remediation: "Document or implement logging, metrics, tracing, health checks, or structured error reporting.",
					Evidence:    []string{"docs or code references for logs, metrics, tracing, health checks, or structured errors"},
					Detect: func(repo string) (bool, string, []string) {
						paths := repoFilesContaining(repo, []string{"metrics", "tracing", "opentelemetry", "sentry", "healthcheck", "health check", "structured log"})
						if len(paths) == 0 {
							return false, "missing runtime signal references", nil
						}
						return true, "found runtime signal references", paths
					},
				},
			},
		},
		{
			ID:    "modularity",
			Title: "Modularity And Interfaces",
			Checks: []readinessCheckSpec{
				{
					ID:          "architecture-boundaries",
					Title:       "Repository documents architecture boundaries.",
					Required:    true,
					Remediation: "Document module boundaries, ownership, and extension points for agents.",
					Evidence:    []string{"docs/architecture.md, docs/module-contracts.md, or README architecture section"},
					Detect: func(repo string) (bool, string, []string) {
						if ok, detail, evidence := checkAnyPaths(repo, []string{"docs/architecture.md", "docs/module-contracts.md"}, "found architecture boundary docs", "missing architecture boundary docs"); ok {
							return ok, detail, evidence
						}
						paths := docsContaining(repo, []string{"architecture", "module", "boundary", "interface"})
						if len(paths) == 0 {
							return false, "missing architecture boundary docs", nil
						}
						return true, "found architecture boundary docs", paths
					},
				},
				{
					ID:          "adapter-shape",
					Title:       "Repository exposes clear interfaces or adapters.",
					Required:    false,
					Remediation: "Name stable interfaces, adapters, commands, or contracts agents should use instead of internals.",
					Evidence:    []string{"interface, adapter, contract, schema, or command boundary in docs or code"},
					Detect: func(repo string) (bool, string, []string) {
						paths := repoFilesContaining(repo, []string{"interface", "adapter", "contract", "schema", "command"})
						if len(paths) == 0 {
							return false, "missing clear interface or adapter signals", nil
						}
						return true, "found interface or adapter signals", paths
					},
				},
			},
		},
		{
			ID:    "evidence",
			Title: "Evidence Workflow",
			Checks: []readinessCheckSpec{
				{
					ID:          "evidence-packets",
					Title:       "Repository has evidence packet artifacts.",
					Required:    true,
					Remediation: "Run `gradient capture` to produce evidence packets.",
					Detect: func(repo string) (bool, string, []string) {
						paths := globRel(repo, ".gradient/evidence/*.json")
						if len(paths) == 0 {
							return false, "missing evidence packet artifacts", nil
						}
						return true, "found evidence packet artifacts", paths
					},
				},
				{
					ID:          "policy-outcomes",
					Title:       "Repository has policy outcomes linked to evidence.",
					Required:    true,
					Remediation: "Capture policy outcomes under `.gradient/policy/`.",
					Detect: func(repo string) (bool, string, []string) {
						paths := globRel(repo, ".gradient/policy/*.json")
						if len(paths) == 0 {
							return false, "missing policy outcomes", nil
						}
						return true, "found policy outcomes", paths
					},
				},
				{
					ID:          "run-and-context",
					Title:       "Repository stores run and context artifacts.",
					Required:    false,
					Remediation: "Capture fleet run and context bundle artifacts.",
					Detect: func(repo string) (bool, string, []string) {
						run := globRel(repo, ".gradient/runs/*/run.json")
						ctx := globRel(repo, ".gradient/context/*.json")
						if len(run) == 0 || len(ctx) == 0 {
							return false, "missing run/context artifacts", nil
						}
						return true, "found run/context artifacts", append(run, ctx...)
					},
				},
				{
					ID:          "eval-fixtures",
					Title:       "Repository keeps eval fixtures for evidence gates.",
					Required:    false,
					Remediation: "Add eval fixtures such as `trace-fixtures` and readiness fixtures.",
					Detect: func(repo string) (bool, string, []string) {
						return checkAllPaths(repo, []string{"evals/trace-fixtures.json", "evals/readiness-fixtures.json"}, "found eval fixtures", "missing eval fixtures")
					},
				},
			},
		},
	}
}

func findTestArtifacts(repo string) []string {
	paths := append(globRel(repo, "scripts/test-*.sh"), globRel(repo, "scripts/*_test.sh")...)
	_ = filepath.WalkDir(repo, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			switch d.Name() {
			case ".git", "node_modules", "dist", ".spellbook":
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if strings.HasSuffix(name, "_test.go") || strings.Contains(name, ".spec.") || strings.Contains(name, ".test.") {
			paths = append(paths, toRepoRel(repo, path))
			if len(paths) >= 12 {
				return errReadinessFound
			}
		}
		return nil
	})
	sort.Strings(paths)
	if len(paths) > 6 {
		return paths[:6]
	}
	return paths
}

func docsContaining(repo string, needles []string) []string {
	var candidates []string
	for _, relPath := range []string{"README.md", "AGENTS.md", "CONTRIBUTING.md"} {
		if exists(filepath.Join(repo, relPath)) {
			candidates = append(candidates, filepath.Join(repo, relPath))
		}
	}
	candidates = append(candidates, globAbs(repo, "docs/*.md")...)
	return filesContaining(repo, candidates, needles, 6)
}

func repoFilesContaining(repo string, needles []string) []string {
	var candidates []string
	_ = filepath.WalkDir(repo, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			switch d.Name() {
			case ".git", ".gradient", "node_modules", "dist", "build", "vendor":
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if strings.HasSuffix(name, ".md") || strings.HasSuffix(name, ".go") || strings.HasSuffix(name, ".ts") || strings.HasSuffix(name, ".tsx") || strings.HasSuffix(name, ".js") || strings.HasSuffix(name, ".json") || strings.HasSuffix(name, ".yaml") || strings.HasSuffix(name, ".yml") {
			candidates = append(candidates, path)
		}
		return nil
	})
	return filesContaining(repo, candidates, needles, 6)
}

func filesContaining(repo string, candidates []string, needles []string, limit int) []string {
	var out []string
	for _, path := range candidates {
		b, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		text := strings.ToLower(string(b))
		for _, needle := range needles {
			if strings.Contains(text, strings.ToLower(needle)) {
				out = append(out, toRepoRel(repo, path))
				break
			}
		}
		if len(out) >= limit {
			break
		}
	}
	sort.Strings(out)
	return out
}

func checkAllPaths(repo string, relPaths []string, passDetail, failDetail string) (bool, string, []string) {
	found := findExistingPaths(repo, relPaths)
	if len(found) != len(relPaths) {
		return false, failDetail, found
	}
	return true, passDetail, found
}

func checkAnyPaths(repo string, relPaths []string, passDetail, failDetail string) (bool, string, []string) {
	found := findExistingPaths(repo, relPaths)
	if len(found) == 0 {
		return false, failDetail, nil
	}
	return true, passDetail, found
}

func findExistingPaths(repo string, relPaths []string) []string {
	out := make([]string, 0, len(relPaths))
	for _, relPath := range relPaths {
		path := filepath.Join(repo, relPath)
		if exists(path) {
			out = append(out, relPath)
		}
	}
	return out
}

func globRel(repo, pattern string) []string {
	abs := globAbs(repo, pattern)
	out := make([]string, 0, len(abs))
	for _, path := range abs {
		out = append(out, toRepoRel(repo, path))
	}
	return out
}

func globAbs(repo, pattern string) []string {
	matches, _ := filepath.Glob(filepath.Join(repo, pattern))
	sort.Strings(matches)
	return matches
}

func toRepoRel(repo, target string) string {
	relPath, err := filepath.Rel(repo, target)
	if err != nil {
		return filepath.ToSlash(target)
	}
	return filepath.ToSlash(relPath)
}
