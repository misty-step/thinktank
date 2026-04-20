# Reachability Analysis

Determine whether a vulnerability actually affects the project. Most CVEs
are in functions the project never calls — upgrading them is noise reduction,
not security hardening.

## Input

The orchestrator provides:
- Package name and version range under review
- CVE identifier(s) and affected function(s) from advisory
- Detected ecosystem (determines which tracing commands to use)

## The Core Insight

Endor Labs research: **92-97% of open-source vulnerabilities are in
functions that consuming applications never call.** A CVE in `lodash.template`
doesn't matter if you only import `lodash.get`. Reachability analysis
turns a wall of CVE alerts into a short, actionable list.

## Levels of Analysis

From coarse to precise:

| Level | Method | Confidence | Cost |
|-------|--------|------------|------|
| Module-level | Does `import X` or `require('X')` appear? | Low — many false positives | Seconds |
| Export-level | Which specific exports are imported? | Medium | Minutes |
| Function-level | Is the vulnerable function in any call chain? | High | Minutes to hours |
| Path-level | Is there an executable path from entry point to vulnerable function? | Highest | Expensive — rarely needed |

For most dependency audits, **export-level** is the sweet spot. Function-level
for critical/high CVEs only.

## How To Do It

### Step 1: Identify the Vulnerable Function

Read the CVE advisory. It names the affected function or module. Examples:
- CVE-2021-23337: `lodash.template` (prototype pollution)
- CVE-2022-46175: `json5.parse` (prototype pollution)
- CVE-2024-4068: `braces.expand` (ReDoS)

If the advisory is vague ("affects versions < X"), check the fix commit
to identify which functions changed.

### Step 2: Check Direct Imports

Search the codebase for imports of the affected package using your ecosystem's import pattern.

No imports found → **not reachable** (for direct deps). But check: is it
a transitive dependency pulled in by something you DO import?

### Step 3: Trace to Specific Exports

Narrow from package-level to the specific vulnerable function or export. Search for uses of that exact export in the codebase.

If the vulnerable export is never used → **not reachable**.

### Step 4: Check Transitive Exposure

The project may not import the vulnerable package directly, but a
dependency might. Use dependency tree commands (`npm ls`, `pip show`,
`go mod graph`, `cargo tree -i`) to find the chain.

If transitive: trace the chain. Does the intermediary dependency invoke
the vulnerable function? Check the intermediary's source.

## Ecosystem-Specific Patterns

### npm / Node.js
- `node_modules` makes transitive deps easy to audit: read the intermediary's source
- `npm audit` reports transitives but doesn't check reachability
- Tree-shaking may eliminate vulnerable code in production builds — but
  server-side code isn't tree-shaken, so don't assume

### Python
- Flat namespace makes import tracing straightforward
- `pip-audit` + `pip show` for dependency chain
- Virtual environments isolate analysis to project deps

### Go
- `govulncheck` does **function-level reachability** natively — use it
- Most accurate out-of-the-box reachability of any ecosystem
- Reports only vulnerabilities in functions your code actually calls

### Rust
- `cargo audit` reports by crate, not by function
- `cargo tree -i <crate>` shows the dependency chain
- Rust's strong typing makes unused imports a compile error, reducing
  false positives

## Decision Tree

```
CVE reported in package X
│
├─ Does the project import X directly?
│  ├─ No → Is X a transitive dep?
│  │       ├─ No → NOT REACHABLE (phantom dep in advisory)
│  │       └─ Yes → Does the intermediary call the vulnerable function?
│  │               ├─ No / Unknown → LIKELY NOT REACHABLE (note uncertainty)
│  │               └─ Yes → REACHABLE via transitive chain
│  │
│  └─ Yes → Does the project use the vulnerable export/function?
│           ├─ No → NOT REACHABLE (import exists but vulnerable code unused)
│           └─ Yes → Is it in a hot path or edge case?
│                    ├─ Hot path → REACHABLE — HIGH PRIORITY
│                    └─ Edge case → REACHABLE — MEDIUM PRIORITY
```

## Output Format

For each CVE analyzed, report:

```markdown
### CVE-YYYY-NNNNN: <package> (<severity>)

**Vulnerable function:** `package.functionName`
**Reachability:** Reachable | Not reachable | Unknown
**Evidence:**
- Import found: `src/utils.ts:12` imports `lodash.template`
- Call chain: `handleRequest` → `renderTemplate` → `lodash.template`
- OR: No imports of `lodash.template` found in codebase
**Recommendation:** Upgrade (reachable) | Upgrade opportunistically (not reachable) | Investigate (unknown)
```

## When to Escalate

- **Unknown reachability after analysis:** The intermediary is complex or
  obfuscated. Note "unknown" and recommend upgrading defensively.
- **Reachable + Critical severity:** This is a real vulnerability. Upgrade
  immediately, even if it requires a major version bump.
- **Transitive chain longer than 3 hops:** Confidence drops with each hop.
  Note the chain length and recommend upgrading the closest direct dep
  that would eliminate the transitive.
