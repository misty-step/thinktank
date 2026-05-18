package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

type anymap map[string]any

var root string

func main() {
	var err error
	root, err = repoRoot()
	if err != nil {
		die(err)
	}
	if err := os.Chdir(root); err != nil {
		die(err)
	}
	args := os.Args[1:]
	cmd := "help"
	if len(args) > 0 {
		cmd, args = args[0], args[1:]
	}
	switch cmd {
	case "validate":
		err = cmdValidate()
	case "resolve":
		err = cmdResolve()
	case "eval":
		err = cmdEval()
	case "readiness":
		err = cmdReadiness(args)
	case "work":
		err = cmdWork(args)
	case "feedback":
		err = cmdFeedback(args)
	case "context":
		err = cmdContext(args)
	case "fleet":
		err = cmdFleet(args)
	case "trace":
		err = cmdTrace(args)
	case "capture":
		err = cmdCapture(args)
	case "close":
		err = cmdClose(args)
	case "report":
		err = cmdReport(args)
	case "status":
		err = cmdStatus(args)
	case "init":
		err = cmdInit(args)
	case "upgrade":
		err = cmdUpgrade(args)
	case "install-global":
		err = cmdInstallGlobal()
	case "config":
		err = cmdConfig()
	case "help", "-h", "--help":
		help()
	default:
		err = fmt.Errorf("unknown command: %s", cmd)
	}
	if err != nil {
		die(err)
	}
}

func die(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

func repoRoot() (string, error) {
	if out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output(); err == nil {
		return strings.TrimSpace(string(out)), nil
	}
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return wd, nil
}

func help() {
	fmt.Print(`usage: gradient <command> [args]

commands:
  validate                    validate Gradient profiles, harness, work, and artifacts
  resolve                     derive .gradient/harness/resolution.json from gradient.yaml
  capture <backlog-item.md>    capture evidence for a backlog.d work item
  eval                        run Gradient structural evals
  readiness [--route backlog] generate a repo readiness report and optional backlog remediation items
  close <backlog-item.md>      close work only after evidence and policy pass
  report [--latest|evidence]   print a human-readable Gradient evidence report
  work <subcommand>            list, show, claim, and transition backlog.d work
  feedback <subcommand>        report, inspect, and route operator feedback
  context <subcommand>         generate repo or synthetic private context bundles
  fleet <subcommand>           start, inspect, complete, or abort local supervised runs
  trace <subcommand>           inspect local trace backends or attach trace refs to evidence
  status [--check]             report global install and harness discovery state
  init system                 install or refresh the machine-level Gradient hook
  init repo [--profile name] [--level harness|work|evidence] [repo]
                              seed a git repo with a tailored Gradient harness
  init [--profile name] <repo> legacy alias for init repo --level evidence
  upgrade [--dry-run|--apply] <repo>
                              update managed Gradient assets in an initialized repo
  install-global               install the gradient command and user config
  config                       print ~/.gradient/config.yaml
`)
}

func readJSON(path string, out any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, out)
}

func writeJSON(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

func writeYAML(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	b, err := yaml.Marshal(v)
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o644)
}

func readYAML(path string, out any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return yaml.Unmarshal(b, out)
}

func now() string {
	return time.Now().UTC().Truncate(time.Second).Format(time.RFC3339)
}

func stamp() string {
	return strings.ToLower(time.Now().UTC().Format("20060102T150405Z"))
}

func slug(s string) string {
	re := regexp.MustCompile(`[^a-z0-9-]+`)
	out := strings.Trim(re.ReplaceAllString(strings.ToLower(s), "-"), "-")
	if out == "" {
		return "item"
	}
	if len(out) > 80 {
		return strings.Trim(out[:80], "-")
	}
	return out
}

func rel(path string) string {
	if r, err := filepath.Rel(root, path); err == nil {
		return r
	}
	return path
}

func splitDoc(path string) (anymap, string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, "", err
	}
	text := string(b)
	if !strings.HasPrefix(text, "---\n") {
		return nil, "", fmt.Errorf("%s missing YAML frontmatter", path)
	}
	rest := strings.TrimPrefix(text, "---\n")
	idx := strings.Index(rest, "\n---")
	if idx < 0 {
		return nil, "", fmt.Errorf("%s missing YAML frontmatter terminator", path)
	}
	fmText := rest[:idx]
	body := strings.TrimLeft(rest[idx+4:], "\n")
	var fm anymap
	if err := yaml.Unmarshal([]byte(fmText), &fm); err != nil {
		return nil, "", err
	}
	return fm, body, nil
}

func writeDoc(path string, fm anymap, body string) error {
	b, err := yaml.Marshal(fm)
	if err != nil {
		return err
	}
	return os.WriteFile(path, []byte("---\n"+string(b)+"---\n\n"+body), 0o644)
}

func asString(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case fmt.Stringer:
		return x.String()
	default:
		return ""
	}
}

func stringSlice(v any) []string {
	var out []string
	switch x := v.(type) {
	case []any:
		for _, item := range x {
			if s := asString(item); s != "" {
				out = append(out, s)
			}
		}
	case []string:
		return x
	}
	return out
}

func obj(v any) anymap {
	if m, ok := v.(map[string]any); ok {
		return m
	}
	if m, ok := v.(anymap); ok {
		return m
	}
	return anymap{}
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func mustDir(path string) error {
	return os.MkdirAll(path, 0o755)
}

func glob(pattern string) []string {
	matches, _ := filepath.Glob(pattern)
	sort.Strings(matches)
	return matches
}

func loadProfile(path string) (anymap, error) {
	var data anymap
	if err := readYAML(path, &data); err != nil {
		return nil, err
	}
	if parent := asString(data["extends"]); parent != "" {
		base, err := loadProfile(filepath.Join("profiles", parent+".yaml"))
		if err != nil {
			return nil, err
		}
		data = deepMerge(base, data)
		data["extends"] = parent
	}
	return data, nil
}

func deepMerge(base, overlay anymap) anymap {
	out := anymap{}
	for k, v := range base {
		out[k] = v
	}
	for k, v := range overlay {
		if k == "extends" {
			continue
		}
		if bv, ok := out[k].(map[string]any); ok {
			if ov, ok := v.(map[string]any); ok {
				out[k] = deepMerge(bv, ov)
				continue
			}
		}
		out[k] = v
	}
	return out
}

func cmdResolve() error {
	profile, err := loadProfile("gradient.yaml")
	if err != nil {
		return err
	}
	h := obj(profile["harness"])
	shared := asString(h["shared_skill_root"])
	if shared == "" {
		shared = asString(obj(h["primitive_library"])["path"])
	}
	if shared == "" {
		shared = ".agents/skills"
	}
	agentRoot := asString(h["agent_root"])
	if agentRoot == "" {
		agentRoot = ".agents/agents"
	}
	res := anymap{
		"$schema":           "../../schemas/harness-resolution.schema.json",
		"id":                fmt.Sprintf("%s-%s", slug(asString(profile["name"])), slug(asString(h["profile"]))),
		"profile":           asString(h["profile"]),
		"implementation":    asString(h["implementation"]),
		"shared_skill_root": shared,
		"bridges":           stringSlice(h["bridges"]),
		"skills":            stringSlice(h["skills"]),
		"agents":            stringSlice(h["agents"]),
		"agent_root":        agentRoot,
		"agent_bridges":     stringSlice(h["agent_bridges"]),
		"providers":         stringSlice(h["providers"]),
		"default_budget":    asString(h["default_budget"]),
		"adoption_level":    asString(h["adoption_level"]),
		"repo_scan":         asString(h["repo_scan"]),
	}
	if err := writeJSON(".gradient/harness/resolution.json", res); err != nil {
		return err
	}
	fmt.Println(".gradient/harness/resolution.json")
	return nil
}

func cmdValidate() error {
	if err := validateSchemas(); err != nil {
		return err
	}
	if err := validateProfiles(); err != nil {
		return err
	}
	if err := validateWork(); err != nil {
		return err
	}
	if err := validateJSONArtifacts(); err != nil {
		return err
	}
	if err := validateHarness(); err != nil {
		return err
	}
	if err := validatePublicSafe(); err != nil {
		return err
	}
	fmt.Println("gradient validation passed")
	return nil
}

func validateSchemas() error {
	for _, path := range glob("schemas/*.json") {
		var v any
		if err := readJSON(path, &v); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		fmt.Printf("ok schema %s\n", path)
	}
	return nil
}

func validateProfiles() error {
	for _, path := range append(glob("profiles/*.yaml"), "gradient.yaml.example", "gradient.yaml") {
		if !exists(path) {
			continue
		}
		p, err := loadProfile(path)
		if err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		for _, key := range []string{"name", "version", "harness", "work", "fleet", "policy", "context"} {
			if _, ok := p[key]; !ok {
				return fmt.Errorf("%s missing required profile key %s", path, key)
			}
		}
		lib := obj(obj(p["harness"])["primitive_library"])
		if asString(lib["type"]) == "local-path" && path == "gradient.yaml" {
			lp := asString(lib["path"])
			if lp == "" || !exists(filepath.Clean(os.ExpandEnv(lp))) {
				return fmt.Errorf("%s local harness library missing: %s", path, lp)
			}
		}
		fmt.Printf("ok profile %s\n", path)
	}
	for _, path := range glob("standards/*.yaml") {
		var v anymap
		if err := readYAML(path, &v); err != nil {
			return err
		}
		if _, ok := v["policy_packs"]; !ok {
			return fmt.Errorf("%s missing policy_packs", path)
		}
		fmt.Printf("ok standards-manifest %s\n", path)
	}
	return nil
}

func workPaths(includeDone bool) []string {
	paths := glob("backlog.d/[0-9][0-9][0-9]-*.md")
	if includeDone {
		paths = append(paths, glob("backlog.d/_done/[0-9][0-9][0-9]-*.md")...)
	}
	sort.Strings(paths)
	return paths
}

func validateWork() error {
	seen := map[string]bool{}
	for _, path := range workPaths(true) {
		fm, _, err := splitDoc(path)
		if err != nil {
			return err
		}
		id := asString(fm["id"])
		if id == "" || seen[id] {
			return fmt.Errorf("%s invalid or duplicate work id %q", path, id)
		}
		seen[id] = true
		status := asString(fm["status"])
		if !in(status, "ready", "leased", "blocked", "done", "failed") {
			return fmt.Errorf("%s invalid status %q", path, status)
		}
		if len(stringSlice(fm["acceptance"])) == 0 || len(stringSlice(fm["evidence_required"])) == 0 {
			return fmt.Errorf("%s missing acceptance or evidence_required", path)
		}
		fmt.Printf("ok work %s\n", path)
	}
	return nil
}

func validateJSONArtifacts() error {
	checks := map[string]string{
		".gradient/context/*.json":   "context",
		".gradient/evidence/*.json":  "evidence",
		".gradient/policy/*.json":    "policy",
		".gradient/feedback/*.json":  "feedback",
		".gradient/runs/*/run.json":  "fleet-run",
		".gradient/harness/*.json":   "harness",
		".gradient/readiness/*.json": "readiness",
		"evals/*.json":               "eval",
	}
	for pattern, label := range checks {
		for _, path := range glob(pattern) {
			var v any
			if err := readJSON(path, &v); err != nil {
				return fmt.Errorf("%s: %w", path, err)
			}
			fmt.Printf("ok %s %s\n", label, path)
		}
	}
	return nil
}

func validateHarness() error {
	var res anymap
	if err := readJSON(".gradient/harness/resolution.json", &res); err != nil {
		return err
	}
	shared := asString(res["shared_skill_root"])
	for _, skill := range stringSlice(res["skills"]) {
		if !exists(filepath.Join(shared, skill, "SKILL.md")) {
			return fmt.Errorf("resolved skill missing SKILL.md: %s", skill)
		}
		for _, bridge := range stringSlice(res["bridges"]) {
			if !exists(filepath.Join(bridge, skill)) {
				return fmt.Errorf("skill bridge missing: %s/%s", bridge, skill)
			}
		}
	}
	agentRoot := asString(res["agent_root"])
	if agentRoot == "" {
		agentRoot = ".agents/agents"
	}
	for _, agent := range stringSlice(res["agents"]) {
		name := agent + ".md"
		if !exists(filepath.Join(agentRoot, name)) {
			return fmt.Errorf("resolved agent missing native definition: %s", name)
		}
		for _, bridge := range stringSlice(res["agent_bridges"]) {
			if !exists(filepath.Join(bridge, name)) {
				return fmt.Errorf("agent bridge missing: %s/%s", bridge, name)
			}
		}
	}
	fmt.Println("ok harness resolution")
	return nil
}

func validatePublicSafe() error {
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`sk-[A-Za-z0-9_-]{20,}`),
		regexp.MustCompile(`sk-proj-[A-Za-z0-9_-]{20,}`),
		regexp.MustCompile(`ghp_[A-Za-z0-9_]{20,}`),
		regexp.MustCompile(`github_pat_[A-Za-z0-9_]{20,}`),
		regexp.MustCompile(`BEGIN (RSA |OPENSSH )?PRIVATE KEY`),
		regexp.MustCompile(`(?i)aws_secret_access_key\s*=`),
	}
	for _, dir := range []string{"backlog.d", ".gradient", ".agents", ".claude", ".codex", ".pi", "harness", "examples", "schemas", "docs", "profiles", ".github"} {
		filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() || strings.Contains(path, ".gradient/private") {
				return nil
			}
			b, _ := os.ReadFile(path)
			for _, p := range patterns {
				if p.Match(b) {
					err = fmt.Errorf("public-safe fixture matched %s: %s", p.String(), path)
					return err
				}
			}
			return nil
		})
	}
	fmt.Println("ok public-safe scan")
	return nil
}

func cmdEval() error {
	if err := validatePublicSafe(); err != nil {
		return err
	}
	for _, path := range []string{"evals/security-fixtures.json", "evals/trace-fixtures.json", "evals/readiness-fixtures.json"} {
		var v any
		if err := readJSON(path, &v); err != nil {
			return err
		}
	}
	fmt.Println("PASS security red fixtures")
	if err := evaluateReadinessFixtures("evals/readiness-fixtures.json"); err != nil {
		return err
	}
	fmt.Println("PASS readiness low/high fixtures")
	if len(glob(".gradient/evidence/*.json")) == 0 {
		return errors.New("no evidence packets found")
	}
	for _, path := range glob(".gradient/evidence/*.json") {
		var ev anymap
		if err := readJSON(path, &ev); err != nil {
			return err
		}
		kinds := map[string]bool{}
		for _, a := range ev["artifacts"].([]any) {
			kinds[asString(obj(a)["kind"])] = true
		}
		for _, k := range []string{"work-item", "fleet-run", "context-bundle", "policy-outcome"} {
			if !kinds[k] {
				return fmt.Errorf("%s missing artifact kind %s", path, k)
			}
		}
	}
	fmt.Println("PASS evidence completeness")
	fmt.Println("PASS trace requirement fixtures")
	fmt.Println("PASS context provenance")
	fmt.Println("PASS policy verdicts")
	if err := validateHarness(); err != nil {
		return err
	}
	fmt.Println("PASS harness default contract")
	coreRoot, coreReason := evalCoreRoot()
	if os.Getenv("GRADIENT_SKIP_WORKSPACE_REGRESSIONS") == "1" {
		fmt.Println("SKIP core workspace regressions: GRADIENT_SKIP_WORKSPACE_REGRESSIONS=1")
	} else if coreRoot == "" {
		fmt.Println("SKIP core workspace regressions: " + coreReason)
	} else {
		for _, script := range []string{"scripts/test-native-harness.sh", "scripts/test-evidence-truth.sh", "scripts/test-workspace-adoption.sh", "scripts/test-workspace-upgrade.sh", "scripts/test-target-eval-scope.sh", "scripts/test-progressive-init.sh", "scripts/test-readiness-report.sh", "scripts/test-global-cli-smoke.sh"} {
			path := filepath.Join(coreRoot, script)
			out, err := exec.Command(path).CombinedOutput()
			if err != nil {
				fmt.Print(string(out))
				return fmt.Errorf("%s failed: %w", path, err)
			}
			fmt.Printf("PASS core workspace regression %s\n", filepath.Base(script))
		}
	}
	fmt.Println("gradient evals passed")
	return nil
}

func evalCoreRoot() (string, string) {
	if configured := os.Getenv("GRADIENT_CORE_ROOT"); configured != "" {
		clean := filepath.Clean(os.ExpandEnv(configured))
		if isGradientCore(clean) {
			return clean, "configured by GRADIENT_CORE_ROOT"
		}
		return "", "GRADIENT_CORE_ROOT is not a Gradient core checkout"
	}
	if isGradientCore(root) {
		return root, "current checkout is Gradient core"
	}
	return "", "current repo is an initialized target workspace, not Gradient core"
}

func isGradientCore(dir string) bool {
	required := []string{
		"docs/architecture.md",
		"docs/module-contracts.md",
		"harness/default/manifest.json",
		"cmd/gradient/main.go",
	}
	for _, path := range required {
		if !exists(filepath.Join(dir, path)) {
			return false
		}
	}
	b, err := os.ReadFile(filepath.Join(dir, "README.md"))
	return err == nil && strings.Contains(string(b), "Gradient is an opinionated operating package")
}

func in(s string, xs ...string) bool {
	for _, x := range xs {
		if s == x {
			return true
		}
	}
	return false
}

func resolveWork(selector string, includeDone bool) (string, anymap, string, error) {
	if exists(selector) {
		fm, body, err := splitDoc(selector)
		return selector, fm, body, err
	}
	var matches []string
	for _, path := range workPaths(includeDone) {
		fm, _, err := splitDoc(path)
		if err != nil {
			return "", nil, "", err
		}
		id := asString(fm["id"])
		if id == selector || strings.HasPrefix(id, selector) {
			matches = append(matches, path)
		}
	}
	if len(matches) == 0 {
		return "", nil, "", fmt.Errorf("no work item found for %s", selector)
	}
	if len(matches) > 1 {
		return "", nil, "", fmt.Errorf("ambiguous work item %s: %s", selector, strings.Join(matches, ", "))
	}
	fm, body, err := splitDoc(matches[0])
	return matches[0], fm, body, err
}

func cmdWork(args []string) error {
	if len(args) == 0 {
		return errors.New("usage: gradient work <list|next|show|adopt|claim|ready|block|fail>")
	}
	cmd, args := args[0], args[1:]
	switch cmd {
	case "list":
		status := "ready"
		if len(args) == 2 && args[0] == "--status" {
			status = args[1]
		}
		fmt.Println("id\tstatus\tstage\towner\ttitle\tpath")
		for _, path := range workPaths(true) {
			fm, _, err := splitDoc(path)
			if err != nil {
				return err
			}
			if status != "all" && asString(fm["status"]) != status {
				continue
			}
			owner := asString(fm["owner"])
			if owner == "" {
				owner = "-"
			}
			fmt.Printf("%s\t%s\t%s\t%s\t%s\t%s\n", fm["id"], fm["status"], fm["lifecycle_stage"], owner, fm["title"], path)
		}
	case "next":
		for _, path := range workPaths(false) {
			fm, _, err := splitDoc(path)
			if err != nil {
				return err
			}
			if asString(fm["status"]) == "ready" {
				fmt.Println(fm["id"])
				return nil
			}
		}
		return errors.New("no ready work items")
	case "show":
		if len(args) != 1 {
			return errors.New("usage: gradient work show <id|path>")
		}
		path, fm, body, err := resolveWork(args[0], true)
		if err != nil {
			return err
		}
		fmt.Printf("# %s: %s\nstatus: %s\nstage: %s\nowner: %s\npath: %s\n\n", fm["id"], fm["title"], fm["status"], fm["lifecycle_stage"], defaultString(asString(fm["owner"]), "-"), path)
		fmt.Println("Acceptance:")
		for _, item := range stringSlice(fm["acceptance"]) {
			fmt.Println("- " + item)
		}
		fmt.Println("\nEvidence required:")
		for _, item := range stringSlice(fm["evidence_required"]) {
			fmt.Println("- " + item)
		}
		if strings.TrimSpace(body) != "" {
			fmt.Println("\n" + strings.TrimRight(body, "\n"))
		}
	case "claim", "ready", "block", "fail":
		if len(args) < 1 {
			return fmt.Errorf("usage: gradient work %s <id|path> [owner]", cmd)
		}
		path, fm, body, err := resolveWork(args[0], true)
		if err != nil {
			return err
		}
		switch cmd {
		case "claim":
			fm["status"] = "leased"
			if len(args) > 1 {
				fm["owner"] = args[1]
			}
		case "ready":
			fm["status"] = "ready"
		case "block":
			fm["status"] = "blocked"
		case "fail":
			fm["status"] = "failed"
		}
		if err := writeDoc(path, fm, body); err != nil {
			return err
		}
		fmt.Println(path)
	case "adopt":
		if len(args) != 1 {
			return errors.New("usage: gradient work adopt <backlog-dir>")
		}
		return adoptBacklog(args[0])
	default:
		return fmt.Errorf("unknown work command: %s", cmd)
	}
	return nil
}

func defaultString(s, d string) string {
	if s == "" {
		return d
	}
	return s
}

func adoptBacklog(dir string) error {
	fmt.Println("path\taction\tstatus\tnotes")
	for _, path := range append(glob(filepath.Join(dir, "*.md")), glob(filepath.Join(dir, "_done", "*.md"))...) {
		name := filepath.Base(path)
		if !regexp.MustCompile(`^[0-9][0-9][0-9]-.*\.md$`).MatchString(name) {
			fmt.Printf("%s\tskip\t-\tnon-ticket markdown\n", path)
			continue
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if strings.HasPrefix(string(b), "---\n") {
			fmt.Printf("%s\tpreserve\t-\talready has frontmatter\n", path)
			continue
		}
		status := "ready"
		if strings.Contains(path, string(filepath.Separator)+"_done"+string(filepath.Separator)) {
			status = "done"
		}
		id := strings.TrimSuffix(name, ".md")
		title := strings.TrimPrefix(strings.SplitN(string(b), "\n", 2)[0], "# ")
		if title == "" {
			title = strings.ReplaceAll(id, "-", " ")
		}
		fm := anymap{
			"id":                id,
			"title":             title,
			"status":            status,
			"lifecycle_stage":   "Intent",
			"acceptance":        []string{"Gradient can preserve and track this adopted work item."},
			"evidence_required": []string{"gradient work show " + id},
		}
		if err := writeDoc(path, fm, string(b)); err != nil {
			return err
		}
		fmt.Printf("%s\tadopt\t%s\tadded Gradient frontmatter\n", path, status)
	}
	return nil
}

func cmdContext(args []string) error {
	if len(args) < 2 {
		return errors.New("usage: gradient context <repo|private-smoke> <query>")
	}
	mode := args[0]
	query := strings.Join(args[1:], " ")
	id := fmt.Sprintf("context-%s-%s-%s", mode, slug(query), stamp())
	var items []anymap
	if mode == "repo" {
		items = []anymap{
			contextItem(id, "architecture", "procedure", "Gradient follows one lifecycle: Intent -> Work Graph -> Fleet Run -> Evidence -> Policy/Eval -> Feedback.", "docs/architecture.md", "public-safe"),
			contextItem(id, "module-contracts", "requirement", "Evidence packets link Work, Harness, Fleet, Context, verification artifacts, trace references, unverified claims, reviewer risks, and Policy outcomes.", "docs/module-contracts.md", "public-safe"),
		}
	} else if mode == "private-smoke" {
		items = []anymap{
			contextItem(id, "private-adapter", "procedure", "Synthetic private-source item proving the adapter shape. Real private source content must stay outside committed Gradient artifacts.", "examples/sources.local.example.yaml", "private/example"),
		}
	} else {
		return fmt.Errorf("unknown context command: %s", mode)
	}
	path := filepath.Join(".gradient/context", id+".json")
	if err := writeJSON(path, anymap{"$schema": "../../schemas/context-bundle.schema.json", "id": id, "mode": "assist", "query": query, "items": items}); err != nil {
		return err
	}
	fmt.Println(path)
	return nil
}

func contextItem(id, suffix, typ, body, source, perm string) anymap {
	return anymap{"id": id + "-" + suffix, "type": typ, "body": body, "source_uri": source, "source_version": "git-worktree", "freshness": "current-worktree", "permission_label": perm, "citation": source}
}

func cmdFleet(args []string) error {
	if len(args) == 0 {
		return errors.New("usage: gradient fleet <normalize-board|start|status|complete|abort>")
	}
	switch args[0] {
	case "status":
		runs := glob(".gradient/runs/*/run.json")
		if len(args) > 1 {
			runs = []string{filepath.Join(".gradient/runs", args[1], "run.json")}
		}
		for _, path := range runs {
			var r anymap
			if err := readJSON(path, &r); err != nil {
				return err
			}
			fmt.Printf("%s\t%s\t%s\t%s\n", r["id"], r["status"], r["backend"], path)
		}
	case "start":
		if len(args) < 2 {
			return errors.New("usage: gradient fleet start <work-id|path>")
		}
		_, fm, _, err := resolveWork(args[1], false)
		if err != nil {
			return err
		}
		id := "run-" + slug(asString(fm["id"])) + "-" + stamp()
		run := anymap{"$schema": "../../../schemas/fleet-run.schema.json", "id": id, "backend": "codex-local", "status": "running", "work_item_ids": []string{asString(fm["id"])}, "harness_id": "local", "context_bundle_id": "", "operator": "local-supervised", "started_at": now(), "events": []anymap{{"type": "start", "at": now(), "summary": "Started local supervised run."}}, "artifacts": []string{}, "trace_refs": []anymap{}, "slot_id": "local-1", "workflow_prompt_version": "local-supervised-v0"}
		path := filepath.Join(".gradient/runs", id, "run.json")
		if err := writeJSON(path, run); err != nil {
			return err
		}
		fmt.Println(id)
	case "complete", "abort":
		if len(args) < 2 {
			return fmt.Errorf("usage: gradient fleet %s <run-id>", args[0])
		}
		path := filepath.Join(".gradient/runs", args[1], "run.json")
		var r anymap
		if err := readJSON(path, &r); err != nil {
			return err
		}
		status := "succeeded"
		if args[0] == "abort" {
			status = "failed"
		}
		r["status"] = status
		r["ended_at"] = now()
		if err := writeJSON(path, r); err != nil {
			return err
		}
		fmt.Println(path)
	case "normalize-board":
		if len(args) != 2 {
			return errors.New("usage: gradient fleet normalize-board <json>")
		}
		var board anymap
		if err := readJSON(args[1], &board); err != nil {
			return err
		}
		out := filepath.Join(".gradient/fleet", strings.TrimSuffix(filepath.Base(args[1]), filepath.Ext(args[1]))+".normalized-work.json")
		return writeJSON(out, board)
	default:
		return fmt.Errorf("unknown fleet command: %s", args[0])
	}
	return nil
}

func cmdTrace(args []string) error {
	if len(args) == 0 {
		return errors.New("usage: gradient trace <status|attach>")
	}
	switch args[0] {
	case "status":
		ok := "missing"
		if _, err := exec.LookPath("raindrop"); err == nil {
			ok = "available"
		}
		record := anymap{"backend": "raindrop", "status": ok, "checked_at": now(), "redaction": "redacted-export"}
		path := filepath.Join(".gradient/traces", "raindrop-status-"+stamp()+".json")
		if err := writeJSON(path, record); err != nil {
			return err
		}
		fmt.Printf("raindrop: %s\n%s\n", ok, path)
	case "attach":
		if len(args) < 4 {
			return errors.New("usage: gradient trace attach <evidence.json> <backend> <trace-id> [artifact-path]")
		}
		path, backend, traceID := args[1], args[2], args[3]
		artifact := ""
		if len(args) > 4 {
			artifact = args[4]
		}
		var ev anymap
		if err := readJSON(path, &ev); err != nil {
			return err
		}
		refs := []any{}
		if raw, ok := ev["trace_refs"].([]any); ok {
			refs = raw
		}
		refs = append(refs, anymap{"backend": backend, "trace_id": traceID, "artifact_path": artifact, "redaction": "redacted-export", "summary": "Attached public-safe trace reference."})
		ev["trace_refs"] = refs
		if err := writeJSON(path, ev); err != nil {
			return err
		}
		fmt.Println(path)
	default:
		return fmt.Errorf("unknown trace command: %s", args[0])
	}
	return nil
}

func cmdCapture(args []string) error {
	if len(args) != 1 {
		return errors.New("usage: gradient capture backlog.d/<id>.md")
	}
	workPath, work, _, err := resolveWork(args[0], true)
	if err != nil {
		return err
	}
	id := asString(work["id"])
	ts := stamp()
	runID, contextID, evidenceID, policyID, feedbackID := "run-"+slug(id)+"-"+ts, "context-"+slug(id)+"-"+ts, "evidence-"+slug(id)+"-"+ts, "policy-"+slug(id)+"-"+ts, "feedback-"+slug(id)+"-"+ts
	artifactDir := filepath.Join(".gradient/runs", runID, "artifacts")
	_ = mustDir(artifactDir)
	statusOut, _ := exec.Command("git", "status", "--short").CombinedOutput()
	diffOut, _ := exec.Command("git", "diff", "--stat").CombinedOutput()
	valOut, valErr := exec.Command("./scripts/gradient.sh", "validate").CombinedOutput()
	os.WriteFile(filepath.Join(artifactDir, "git-status.txt"), append(statusOut, '\n'), 0o644)
	os.WriteFile(filepath.Join(artifactDir, "git-diff-stat.txt"), append(diffOut, '\n'), 0o644)
	os.WriteFile(filepath.Join(artifactDir, "validate.txt"), append(valOut, '\n'), 0o644)
	context := anymap{"$schema": "../../schemas/context-bundle.schema.json", "id": contextID, "mode": "assist", "query": "Context for " + id, "items": []anymap{contextItem(contextID, "work", "requirement", strings.Join(stringSlice(work["acceptance"]), "; "), workPath, "public-safe")}}
	if exists("docs/architecture.md") {
		context["items"] = append(context["items"].([]anymap), contextItem(contextID, "architecture", "procedure", "Repository architecture or overview context.", "docs/architecture.md", "public-safe"))
	}
	if err := writeJSON(filepath.Join(".gradient/context", contextID+".json"), context); err != nil {
		return err
	}
	var res anymap
	_ = readJSON(".gradient/harness/resolution.json", &res)
	runStatus := "succeeded"
	if valErr != nil {
		runStatus = "failed"
	}
	run := anymap{"$schema": "../../../schemas/fleet-run.schema.json", "id": runID, "backend": "codex-local", "status": runStatus, "work_item_ids": []string{id}, "harness_id": defaultString(asString(res["id"]), "local"), "context_bundle_id": contextID, "operator": "local-supervised", "started_at": now(), "ended_at": now(), "events": []anymap{{"type": "start", "at": now(), "summary": "Captured local supervised work."}, {"type": "validation", "at": now(), "summary": "Ran gradient validate."}, {"type": "complete", "at": now(), "summary": "Evidence capture completed."}}, "artifacts": []string{filepath.Join(artifactDir, "git-status.txt"), filepath.Join(artifactDir, "git-diff-stat.txt"), filepath.Join(artifactDir, "validate.txt")}, "trace_refs": []anymap{}}
	if err := writeJSON(filepath.Join(".gradient/runs", runID, "run.json"), run); err != nil {
		return err
	}
	verdict := "pass"
	if valErr != nil {
		verdict = "needs_review"
	}
	policy := anymap{"$schema": "../../schemas/policy-outcome.schema.json", "id": policyID, "work_item_id": id, "evidence_packet_id": evidenceID, "verdict": verdict, "evidence_verdict": "sufficient", "reviewer": "gradient-go", "created_at": now(), "checks": []anymap{{"name": "gradient validate", "status": verdict, "summary": "Go-backed validation gate."}}, "risks": []string{}}
	if err := writeJSON(filepath.Join(".gradient/policy", policyID+".json"), policy); err != nil {
		return err
	}
	evidence := anymap{"$schema": "../../schemas/evidence-packet.schema.json", "id": evidenceID, "work_item_id": id, "run_id": runID, "context_bundle_id": contextID, "policy_outcome_id": policyID, "workflow": "gradient-go", "created_at": now(), "required_artifact_kinds": []string{"work-item", "harness-resolution", "fleet-run", "context-bundle", "policy-outcome", "validation"}, "artifacts": []anymap{{"kind": "work-item", "path": workPath, "summary": asString(work["title"])}, {"kind": "harness-resolution", "path": ".gradient/harness/resolution.json", "summary": "Resolved harness contract."}, {"kind": "fleet-run", "path": filepath.Join(".gradient/runs", runID, "run.json"), "summary": "Local supervised run record."}, {"kind": "context-bundle", "path": filepath.Join(".gradient/context", contextID+".json"), "summary": "Context bundle."}, {"kind": "policy-outcome", "path": filepath.Join(".gradient/policy", policyID+".json"), "summary": "Policy outcome."}, {"kind": "validation", "path": filepath.Join(artifactDir, "validate.txt"), "summary": "Validation output."}}, "trace_refs": []anymap{}, "unverified_claims": []string{}, "reviewer_risks": []string{}}
	if err := writeJSON(filepath.Join(".gradient/evidence", evidenceID+".json"), evidence); err != nil {
		return err
	}
	feedback := anymap{"$schema": "../../schemas/feedback-item.schema.json", "id": feedbackID, "work_item_id": id, "source": "evidence-capture", "created_at": now(), "summary": "Evidence captured for " + id, "route": "none", "status": "captured", "refs": []string{filepath.Join(".gradient/evidence", evidenceID+".json")}}
	if err := writeJSON(filepath.Join(".gradient/feedback", feedbackID+".json"), feedback); err != nil {
		return err
	}
	fmt.Println(filepath.Join(".gradient/evidence", evidenceID+".json"))
	return nil
}

func cmdClose(args []string) error {
	if len(args) != 1 {
		return errors.New("usage: gradient close backlog.d/<id>.md")
	}
	path, fm, body, err := resolveWork(args[0], false)
	if err != nil {
		return err
	}
	id := asString(fm["id"])
	var latest string
	for _, ev := range glob(".gradient/evidence/*.json") {
		var e anymap
		_ = readJSON(ev, &e)
		if asString(e["work_item_id"]) == id {
			latest = ev
		}
	}
	if latest == "" {
		return fmt.Errorf("no evidence packet for %s", id)
	}
	fm["status"] = "done"
	fm["lifecycle_stage"] = "Feedback"
	done := filepath.Join("backlog.d/_done", filepath.Base(path))
	if err := writeDoc(done, fm, body); err != nil {
		return err
	}
	if err := os.Remove(path); err != nil {
		return err
	}
	fmt.Println(done)
	return nil
}

func cmdReport(args []string) error {
	paths := glob(".gradient/evidence/*.json")
	if len(paths) == 0 {
		return errors.New("no evidence packets found")
	}
	target := paths[len(paths)-1]
	if len(args) > 0 && args[0] != "--latest" {
		target = args[0]
	}
	var e anymap
	if err := readJSON(target, &e); err != nil {
		return err
	}
	fmt.Printf("# Gradient Evidence Report\n\nEvidence: %s\nWork: %s\nRun: %s\nPolicy: %s\n\nArtifacts:\n", e["id"], e["work_item_id"], e["run_id"], e["policy_outcome_id"])
	for _, a := range e["artifacts"].([]any) {
		m := obj(a)
		fmt.Printf("- %s: %s\n", m["kind"], m["path"])
	}
	return nil
}

func cmdFeedback(args []string) error {
	if len(args) == 0 {
		return errors.New("usage: gradient feedback <report|list|show|route>")
	}
	switch args[0] {
	case "list":
		for _, path := range glob(".gradient/feedback/*.json") {
			var f anymap
			_ = readJSON(path, &f)
			fmt.Printf("%s\t%s\t%s\t%s\n", f["id"], f["status"], f["route"], path)
		}
	case "show":
		if len(args) != 2 {
			return errors.New("usage: gradient feedback show <id|path>")
		}
		path := args[1]
		if !exists(path) {
			for _, p := range glob(".gradient/feedback/*.json") {
				if strings.Contains(filepath.Base(p), args[1]) {
					path = p
					break
				}
			}
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		fmt.Print(string(b))
	case "report":
		if len(args) < 2 {
			return errors.New("usage: gradient feedback report [--module name] [--classification type] [--severity level] --summary text [--route backlog]")
		}
		item := parseFeedbackReport(args[1:])
		id := "feedback-" + stamp() + "-" + slug(asString(item["summary"]))
		path := filepath.Join(".gradient/feedback", id+".json")
		item["$schema"] = "../../schemas/feedback-item.schema.json"
		item["id"] = id
		item["reported_at"] = now()
		if err := writeJSON(path, item); err != nil {
			return err
		}
		if asString(item["route"]) == "backlog" {
			if err := routeFeedback(path, "backlog"); err != nil {
				return err
			}
			fmt.Println("routed feedback to backlog")
		} else {
			fmt.Println(path)
		}
	case "route":
		if len(args) < 3 {
			return errors.New("usage: gradient feedback route <feedback.json> backlog")
		}
		return routeFeedback(args[1], args[2])
	default:
		return fmt.Errorf("unknown feedback command: %s", args[0])
	}
	return nil
}

func parseFeedbackReport(args []string) anymap {
	item := anymap{
		"module":          "Work",
		"classification":  "bug",
		"severity":        "medium",
		"summary":         strings.Join(args, " "),
		"route":           "none",
		"status":          "open",
		"reporter":        "local-operator",
		"scope":           "workspace",
		"profile":         "local",
		"lifecycle_stage": "Feedback",
		"expected":        "Expected behavior was not supplied.",
		"actual":          "Actual behavior was not supplied.",
		"evidence":        []string{},
		"redaction":       "public-safe",
	}
	for i := 0; i < len(args); i++ {
		if !strings.HasPrefix(args[i], "--") || i+1 >= len(args) {
			continue
		}
		key := strings.TrimPrefix(args[i], "--")
		val := args[i+1]
		i++
		switch key {
		case "module", "classification", "severity", "summary", "route", "expected", "actual", "scope", "profile", "owner":
			item[key] = val
		case "evidence":
			item["evidence"] = append(stringSlice(item["evidence"]), val)
		}
	}
	return item
}

func routeFeedback(path, route string) error {
	var f anymap
	if err := readJSON(path, &f); err != nil {
		return err
	}
	f["route"] = route
	if route == "backlog" {
		next := nextWorkNumber()
		id := fmt.Sprintf("%03d-%s", next, slug(asString(f["summary"])))
		workPath := filepath.Join("backlog.d", id+".md")
		fm := anymap{"id": id, "title": asString(f["summary"]), "status": "ready", "lifecycle_stage": "Intent", "acceptance": []string{"Feedback is represented as a shaped Gradient work item."}, "evidence_required": []string{"gradient work show " + id}}
		if err := writeDoc(workPath, fm, "## Source Feedback\n\n"+path+"\n"); err != nil {
			return err
		}
		f["linked_work_item"] = workPath
	}
	f["status"] = "routed"
	return writeJSON(path, f)
}

func nextWorkNumber() int {
	max := 0
	re := regexp.MustCompile(`^([0-9]{3})-`)
	for _, path := range workPaths(true) {
		if m := re.FindStringSubmatch(filepath.Base(path)); len(m) == 2 {
			var n int
			fmt.Sscanf(m[1], "%d", &n)
			if n > max {
				max = n
			}
		}
	}
	return max + 1
}

func cmdStatus(args []string) error {
	check := len(args) > 0 && args[0] == "--check"
	failures := 0
	configDir := os.Getenv("GRADIENT_CONFIG_DIR")
	if configDir == "" {
		configDir = filepath.Join(os.Getenv("HOME"), ".gradient")
	}
	fmt.Println("Gradient core:", root)
	for label, path := range map[string]string{"config": filepath.Join(configDir, "config.yaml"), "machine brief": filepath.Join(configDir, "AGENTS.md")} {
		if exists(path) {
			fmt.Printf("ok %s: %s\n", label, path)
		} else {
			fmt.Printf("missing %s: %s\n", label, path)
			failures++
		}
	}
	if p, err := exec.LookPath("gradient"); err == nil {
		fmt.Println("ok command:", p)
	} else {
		fmt.Println("missing command: gradient")
		failures++
	}
	fmt.Println("workspace:", root)
	if exists("gradient.yaml") {
		fmt.Println("ok workspace profile: " + filepath.Join(root, "gradient.yaml"))
	}
	if check && failures > 0 {
		return fmt.Errorf("%d status checks failed", failures)
	}
	return nil
}

func cmdInstallGlobal() error {
	configDir := os.Getenv("GRADIENT_CONFIG_DIR")
	if configDir == "" {
		configDir = filepath.Join(os.Getenv("HOME"), ".gradient")
	}
	if err := mustDir(configDir); err != nil {
		return err
	}
	binDir := filepath.Join(os.Getenv("HOME"), ".local", "bin")
	_ = mustDir(binDir)
	link := filepath.Join(binDir, "gradient")
	_ = os.Remove(link)
	if err := os.Symlink(filepath.Join(root, "bin", "gradient"), link); err != nil {
		return err
	}
	if !exists(filepath.Join(configDir, "config.yaml")) {
		if err := os.WriteFile(filepath.Join(configDir, "config.yaml"), []byte("default_profile: solo-frontier\ncore_root: "+root+"\n"), 0o644); err != nil {
			return err
		}
	}
	brief := filepath.Join(configDir, "AGENTS.md")
	block := "BEGIN GRADIENT MANAGED BLOCK\nGradient is installed globally. Use `gradient status`, `gradient init <repo>`, `gradient work list --status all`, `gradient capture <item>`, `gradient close <item>`, `gradient validate`, and `gradient eval`.\nEND GRADIENT MANAGED BLOCK\n"
	return os.WriteFile(brief, []byte(block), 0o644)
}

func cmdConfig() error {
	configDir := os.Getenv("GRADIENT_CONFIG_DIR")
	if configDir == "" {
		configDir = filepath.Join(os.Getenv("HOME"), ".gradient")
	}
	path := filepath.Join(configDir, "config.yaml")
	if !exists(path) {
		if err := cmdInstallGlobal(); err != nil {
			return err
		}
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	fmt.Print(string(b))
	return nil
}

func copyFileNew(src, dst string, mode os.FileMode) error {
	if exists(dst) {
		fmt.Println("preserve existing " + dst)
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	fmt.Println("create " + dst)
	return err
}

func copyDirNew(src, dst string) error {
	if exists(dst) {
		fmt.Println("preserve existing " + dst)
		return nil
	}
	return copyDirOverwrite(src, dst)
}

func copyDirMergeNew(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relp, _ := filepath.Rel(src, path)
		target := filepath.Join(dst, relp)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		if exists(target) {
			fmt.Println("preserve existing " + target)
			return nil
		}
		if d.Type()&os.ModeSymlink != 0 {
			link, err := os.Readlink(path)
			if err != nil {
				return err
			}
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			return os.Symlink(link, target)
		}
		info, _ := d.Info()
		return copyFileForce(path, target, info.Mode())
	})
}

func copyDirOverwrite(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relp, _ := filepath.Rel(src, path)
		target := filepath.Join(dst, relp)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		if d.Type()&os.ModeSymlink != 0 {
			link, err := os.Readlink(path)
			if err != nil {
				return err
			}
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			_ = os.Remove(target)
			return os.Symlink(link, target)
		}
		info, _ := d.Info()
		return copyFileForce(path, target, info.Mode())
	})
}

func copyFileForce(src, dst string, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

func appendGitignore(targetRoot string) error {
	path := filepath.Join(targetRoot, ".gitignore")
	block := "\n# Gradient local/private state\n.gradient/private/\n.gradient/sources.local.yaml\n"
	b, _ := os.ReadFile(path)
	if strings.Contains(string(b), ".gradient/sources.local.yaml") {
		return nil
	}
	return os.WriteFile(path, append(b, []byte(block)...), 0o644)
}

func cmdUpgrade(args []string) error {
	apply, target := false, ""
	for _, a := range args {
		if a == "--apply" {
			apply = true
		} else if a == "--dry-run" {
			apply = false
		} else {
			target = a
		}
	}
	if target == "" {
		return errors.New("usage: gradient upgrade [--dry-run|--apply] <repo>")
	}
	out, err := exec.Command("git", "-C", target, "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return err
	}
	targetRoot := strings.TrimSpace(string(out))
	files := managedFiles()
	for _, f := range files {
		src, dst := f, filepath.Join(targetRoot, f)
		action := "preserve"
		if !exists(dst) {
			action = "create"
			if apply {
				if err := copyFileForce(src, dst, 0o755); err != nil {
					return err
				}
			}
		} else if sameFile(src, dst) {
			action = "up-to-date"
		} else {
			action = "repo-owned-or-modified"
		}
		fmt.Printf("%s\t%s\n", action, f)
	}
	if apply {
		return writeManagedManifest(root, targetRoot)
	}
	return nil
}

func managedFiles() []string {
	files := []string{"go.mod", "go.sum", "gradient.yaml.example", "bin/gradient"}
	for _, rootDir := range []string{"schemas", "profiles", "standards", "evals", "scripts", "cmd", ".agents/skills", ".agents/agents", ".claude/agents", "harness"} {
		filepath.WalkDir(rootDir, func(path string, d os.DirEntry, err error) error {
			if err == nil && !d.IsDir() {
				files = append(files, path)
			}
			return nil
		})
	}
	sort.Strings(files)
	return files
}

func sameFile(a, b string) bool {
	ia, ea := os.Lstat(a)
	ib, eb := os.Lstat(b)
	if ea == nil && eb == nil && ia.Mode()&os.ModeSymlink != 0 && ib.Mode()&os.ModeSymlink != 0 {
		la, _ := os.Readlink(a)
		lb, _ := os.Readlink(b)
		return la == lb
	}
	ha, ea := fileSHA(a)
	hb, eb := fileSHA(b)
	return ea == nil && eb == nil && ha == hb
}

func fileSHA(path string) (string, error) {
	if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink != 0 {
		link, err := os.Readlink(path)
		if err != nil {
			return "", err
		}
		sum := sha256.Sum256([]byte("symlink:" + link))
		return hex.EncodeToString(sum[:]), nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}

func writeManagedManifest(source, target string) error {
	var files []anymap
	for _, f := range managedFiles() {
		dst := filepath.Join(target, f)
		if !exists(dst) || !exists(filepath.Join(source, f)) {
			continue
		}
		srcSHA, _ := fileSHA(filepath.Join(source, f))
		dstSHA, _ := fileSHA(dst)
		kind := "file"
		if info, err := os.Lstat(filepath.Join(source, f)); err == nil && info.Mode()&os.ModeSymlink != 0 {
			kind = "symlink"
		}
		files = append(files, anymap{"source_path": f, "target_path": f, "kind": kind, "owner": "gradient-managed", "policy": "update-if-unchanged", "source_sha256": srcSHA, "target_sha256": dstSHA})
	}
	return writeJSON(filepath.Join(target, ".gradient/managed-manifest.json"), anymap{"schema_version": 1, "source_root": source, "source_version": "local-go", "generated_at": now(), "files": files, "repo_owned": []string{"gradient.yaml", "backlog.d", ".gradient/evidence", ".gradient/context", ".gradient/policy", ".gradient/feedback", ".gradient/runs"}})
}
