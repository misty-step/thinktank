package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

func cmdInit(args []string) error {
	if len(args) > 0 {
		switch args[0] {
		case "system":
			if len(args) != 1 {
				return errors.New("usage: gradient init system")
			}
			return cmdInstallGlobal()
		case "repo":
			return cmdInitRepo(args[1:], "harness")
		}
	}
	return cmdInitRepo(args, "evidence")
}

func cmdInitRepo(args []string, defaultLevel string) error {
	profile, target := "solo-frontier", ""
	level, tailorMode := defaultLevel, "fast"
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--profile" && i+1 < len(args):
			profile, i = args[i+1], i+1
		case args[i] == "--level" && i+1 < len(args):
			level, i = args[i+1], i+1
		case args[i] == "--tailor" && i+1 < len(args):
			tailorMode, i = args[i+1], i+1
		case strings.HasPrefix(args[i], "--"):
			return fmt.Errorf("unknown init option: %s", args[i])
		default:
			target = args[i]
		}
	}
	if target == "" {
		target = "."
	}
	if !validInitLevel(level) {
		return fmt.Errorf("unknown init level %q", level)
	}
	if !in(tailorMode, "none", "fast") {
		return fmt.Errorf("unknown tailor mode %q", tailorMode)
	}
	out, err := exec.Command("git", "-C", target, "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return fmt.Errorf("target must be a git repository: %s", target)
	}
	targetRoot := strings.TrimSpace(string(out))
	fmt.Println("resolved git worktree root:", targetRoot)
	scan := scanRepository(targetRoot)
	dirs := []string{".gradient/harness", ".gradient/init"}
	if initLevelAtLeast(level, "work") {
		dirs = append(dirs, "backlog.d/_done")
	}
	if initLevelAtLeast(level, "evidence") {
		dirs = append(dirs, ".gradient/context", ".gradient/evidence", ".gradient/feedback", ".gradient/policy", ".gradient/runs", "examples/golden-workflows", "scripts/lib")
	}
	for _, d := range dirs {
		if err := os.MkdirAll(filepath.Join(targetRoot, d), 0o755); err != nil {
			return err
		}
	}
	harnessDirs := []string{"schemas", "profiles", "standards", ".agents/skills", ".agents/agents", ".claude/agents", ".claude/skills", ".codex/skills", ".pi/skills", "harness"}
	if initLevelAtLeast(level, "evidence") {
		harnessDirs = append(harnessDirs, "evals", "cmd")
	}
	for _, d := range harnessDirs {
		if exists(d) {
			if err := copyDirMergeNew(d, filepath.Join(targetRoot, d)); err != nil {
				return err
			}
		}
	}
	files := []string{"gradient.yaml", "gradient.yaml.example"}
	if initLevelAtLeast(level, "evidence") {
		files = append(files, "go.mod", "go.sum", "bin/gradient")
	}
	for _, f := range files {
		if exists(f) {
			dst := filepath.Join(targetRoot, f)
			if err := copyFileNew(f, dst, 0o755); err != nil {
				return err
			}
		}
	}
	if initLevelAtLeast(level, "evidence") {
		if err := copyDirOverwrite("scripts", filepath.Join(targetRoot, "scripts")); err != nil {
			return err
		}
	}
	guidancePath := filepath.Join(targetRoot, "AGENTS.md")
	if exists(guidancePath) {
		guidancePath = filepath.Join(targetRoot, "AGENTS.gradient.md")
	}
	if tailorMode != "none" {
		if err := os.WriteFile(guidancePath, []byte(renderRepoGuidance(scan, level, profile)), 0o644); err != nil {
			return err
		}
		fmt.Println("create " + guidancePath)
		if err := writeRepoSkillAndAgent(targetRoot, scan); err != nil {
			return err
		}
	}
	if err := writeJSON(filepath.Join(targetRoot, ".gradient/init/repo-scan.json"), scan); err != nil {
		return err
	}
	gy := filepath.Join(targetRoot, "gradient.yaml")
	if b, err := os.ReadFile(gy); err == nil {
		var data anymap
		if err := yaml.Unmarshal(b, &data); err == nil {
			name := slug(filepath.Base(targetRoot))
			data["name"] = name
			h := obj(data["harness"])
			h["profile"] = profile
			h["adoption_level"] = level
			h["tailor_mode"] = tailorMode
			h["repo_scan"] = ".gradient/init/repo-scan.json"
			h["skills"] = appendUniqueString(stringSlice(h["skills"]), "repo-workflow")
			h["agents"] = appendUniqueString(stringSlice(h["agents"]), "repo-guide")
			data["harness"] = h
			if err := writeYAML(gy, data); err != nil {
				return err
			}
		}
	}
	if err := appendGitignore(targetRoot); err != nil {
		return err
	}
	if initLevelAtLeast(level, "work") && len(glob(filepath.Join(targetRoot, "backlog.d/[0-9][0-9][0-9]-*.md"))) == 0 {
		fm := anymap{"id": "001-gradient-onboarding", "title": "Adopt Gradient for this workspace", "status": "ready", "lifecycle_stage": "Intent", "acceptance": []string{"gradient validate passes in this repo.", "gradient work list shows this item."}, "evidence_required": []string{"gradient validate", "gradient work list --status all"}}
		if err := writeDoc(filepath.Join(targetRoot, "backlog.d/001-gradient-onboarding.md"), fm, "## Notes\n\nInitial Gradient onboarding work item.\n"); err != nil {
			return err
		}
	}
	if initLevelAtLeast(level, "work") {
		if err := adoptBacklog(filepath.Join(targetRoot, "backlog.d")); err != nil {
			return err
		}
	}
	if initLevelAtLeast(level, "work") {
		if err := writeRepoImprovementItem(targetRoot, scan); err != nil {
			return err
		}
	}
	cwd, _ := os.Getwd()
	if err := os.Chdir(targetRoot); err != nil {
		return err
	}
	err = cmdResolve()
	if err == nil {
		err = cmdValidate()
	}
	if manifestErr := writeManagedManifest(root, targetRoot); err == nil {
		err = manifestErr
	}
	if chdirErr := os.Chdir(cwd); err == nil {
		err = chdirErr
	}
	return err
}

func validInitLevel(level string) bool {
	return in(level, "harness", "work", "evidence", "policy", "context-fleet", "org-control-plane")
}

func initLevelAtLeast(level, min string) bool {
	ranks := map[string]int{"harness": 1, "work": 2, "evidence": 3, "policy": 4, "context-fleet": 5, "org-control-plane": 6}
	return ranks[level] >= ranks[min]
}

func scanRepository(targetRoot string) anymap {
	scan := anymap{
		"schema_version":    1,
		"generated_at":      now(),
		"repo_name":         filepath.Base(targetRoot),
		"docs":              existingRelative(targetRoot, []string{"README.md", "README.adoc", "AGENTS.md", "CLAUDE.md", "docs"}),
		"package_manifests": existingRelative(targetRoot, []string{"go.mod", "package.json", "pyproject.toml", "Cargo.toml", "bun.lock", "pnpm-lock.yaml", "yarn.lock", "package-lock.json"}),
		"harness":           existingRelative(targetRoot, []string{".agents", ".claude", ".codex", ".pi", "harness", "gradient.yaml"}),
		"ci":                existingRelative(targetRoot, []string{".github/workflows", ".gitlab-ci.yml", "Taskfile.yml", "Makefile"}),
	}
	scan["languages"] = detectedLanguages(targetRoot)
	scan["commands"] = detectedCommands(targetRoot)
	scan["readiness_hints"] = readinessHints(scan)
	return scan
}

func existingRelative(rootDir string, candidates []string) []string {
	var out []string
	for _, c := range candidates {
		if exists(filepath.Join(rootDir, c)) {
			out = append(out, c)
		}
	}
	return out
}

func detectedLanguages(targetRoot string) []string {
	var langs []string
	checks := map[string]string{"go.mod": "go", "package.json": "javascript", "pyproject.toml": "python", "Cargo.toml": "rust", "build.zig": "zig"}
	for file, lang := range checks {
		if exists(filepath.Join(targetRoot, file)) {
			langs = append(langs, lang)
		}
	}
	sort.Strings(langs)
	return langs
}

func detectedCommands(targetRoot string) []string {
	var commands []string
	if exists(filepath.Join(targetRoot, "go.mod")) {
		commands = append(commands, "go test ./...")
	}
	if exists(filepath.Join(targetRoot, "package.json")) {
		commands = append(commands, "npm test", "npm run lint")
	}
	if exists(filepath.Join(targetRoot, "Cargo.toml")) {
		commands = append(commands, "cargo test")
	}
	if exists(filepath.Join(targetRoot, "Makefile")) {
		commands = append(commands, "make test")
	}
	return commands
}

func readinessHints(scan anymap) []string {
	var hints []string
	if len(stringSlice(scan["docs"])) == 0 {
		hints = append(hints, "Add README or agent-facing onboarding docs.")
	}
	if len(stringSlice(scan["ci"])) == 0 {
		hints = append(hints, "Add a committed CI or validation entrypoint.")
	}
	if len(stringSlice(scan["commands"])) == 0 {
		hints = append(hints, "Declare test, lint, or validation commands.")
	}
	if len(stringSlice(scan["harness"])) == 0 {
		hints = append(hints, "Commit a repo-local agent harness.")
	}
	return hints
}

func renderRepoGuidance(scan anymap, level, profile string) string {
	commands := stringSlice(scan["commands"])
	if len(commands) == 0 {
		commands = []string{"gradient validate"}
	}
	return fmt.Sprintf(`# Gradient Repo Harness

This repository is Gradient-managed at adoption level '%s' with profile '%s'.

## Repo Signals

- Repository: '%s'
- Languages: %s
- Docs: %s
- CI/automation: %s

## Agent Workflow

1. Start by running 'gradient resolve' and 'gradient validate'.
2. Read the repo docs listed above before changing product code.
3. Use the detected verification commands when they apply:

%s

## Gradient Contract

Gradient owns the repo-local harness projection and profile. Existing product
code is repo-owned; initialization logs improvement work instead of silently
editing product implementation.
`, level, profile, asString(scan["repo_name"]), joinOrDash(stringSlice(scan["languages"])), joinOrDash(stringSlice(scan["docs"])), joinOrDash(stringSlice(scan["ci"])), markdownList(commands))
}

func writeRepoSkillAndAgent(targetRoot string, scan anymap) error {
	skillDir := filepath.Join(targetRoot, ".agents/skills/repo-workflow")
	if err := os.MkdirAll(skillDir, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte(renderRepoWorkflowSkill(scan)), 0o644); err != nil {
		return err
	}
	for _, bridge := range []string{".claude/skills", ".codex/skills", ".pi/skills"} {
		if err := linkOrMarker(filepath.Join(targetRoot, bridge, "repo-workflow"), "../../.agents/skills/repo-workflow"); err != nil {
			return err
		}
	}

	agentPath := filepath.Join(targetRoot, ".agents/agents/repo-guide.md")
	if err := os.MkdirAll(filepath.Dir(agentPath), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(agentPath, []byte(renderRepoGuideAgent(scan)), 0o644); err != nil {
		return err
	}
	return linkOrMarker(filepath.Join(targetRoot, ".claude/agents/repo-guide.md"), "../../.agents/agents/repo-guide.md")
}

func renderRepoWorkflowSkill(scan anymap) string {
	commands := stringSlice(scan["commands"])
	if len(commands) == 0 {
		commands = []string{"gradient validate"}
	}
	return fmt.Sprintf(`---
name: repo-workflow
description: Use this repository's Gradient-detected workflow, docs, and verification commands.
user-invocable: true
---

# Repo Workflow

Repository: %s

## Read First

%s

## Verify With

%s

## Rules

- Prefer repository docs and detected commands over generic assumptions.
- Run `+"`gradient resolve`"+` and `+"`gradient validate`"+` before closing Gradient-managed work.
- Log product or readiness improvements as work items instead of silently changing product code during initialization.
`, asString(scan["repo_name"]), markdownList(defaultList(stringSlice(scan["docs"]), "README.md")), markdownList(commands))
}

func renderRepoGuideAgent(scan anymap) string {
	return fmt.Sprintf(`# repo-guide

Use this agent when work requires repository-specific orientation before edits.

Focus:
- repo docs: %s
- languages: %s
- CI/automation: %s

Before implementation, identify the relevant module boundaries, likely
verification commands, and any missing readiness evidence that should become
backlog work instead of silent product-code edits.
`, joinOrDash(stringSlice(scan["docs"])), joinOrDash(stringSlice(scan["languages"])), joinOrDash(stringSlice(scan["ci"])))
}

func defaultList(xs []string, fallback string) []string {
	if len(xs) > 0 {
		return xs
	}
	return []string{fallback}
}

func appendUniqueString(xs []string, value string) []string {
	for _, x := range xs {
		if x == value {
			return xs
		}
	}
	return append(xs, value)
}

func linkOrMarker(path, target string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if exists(path) {
		return nil
	}
	if err := os.Symlink(target, path); err == nil {
		return nil
	}
	return os.WriteFile(path, []byte("See "+target+"\n"), 0o644)
}

func joinOrDash(xs []string) string {
	if len(xs) == 0 {
		return "-"
	}
	return strings.Join(xs, ", ")
}

func markdownList(xs []string) string {
	var b strings.Builder
	for _, x := range xs {
		b.WriteString("- `")
		b.WriteString(x)
		b.WriteString("`\n")
	}
	return strings.TrimRight(b.String(), "\n")
}

func writeRepoImprovementItem(targetRoot string, scan anymap) error {
	hints := stringSlice(scan["readiness_hints"])
	if len(hints) == 0 {
		return nil
	}
	path := filepath.Join(targetRoot, "backlog.d/002-improve-agent-readiness.md")
	if exists(path) {
		return nil
	}
	fm := anymap{
		"id":              "002-improve-agent-readiness",
		"title":           "Improve agent readiness from Gradient init scan",
		"status":          "ready",
		"lifecycle_stage": "Policy/Eval",
		"acceptance":      []string{"The repository has explicit docs, verification commands, harness guidance, and automation appropriate for agent work."},
		"evidence_required": []string{
			"gradient readiness",
			"gradient validate",
		},
	}
	body := "## Init Scan Findings\n\n" + markdownList(hints) + "\n"
	return writeDoc(path, fm, body)
}
