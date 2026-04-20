# Behavioral Diff Analysis

Detect dangerous behavioral changes in dependency upgrades that changelogs
don't mention. Inspired by Socket's approach: analyze what packages
actually do, not just what they claim to do.

## Input

The orchestrator provides:
- Package name with old and new version
- Detected ecosystem
- Whether this is a patch, minor, or major bump

## Why This Matters

A version bump that passes tests can still introduce:
- Install scripts that run arbitrary code
- New network calls phoning home
- Filesystem access outside the project
- Removed exports that break downstream consumers
- Native dependency additions that break cross-platform builds
- Permission escalation in CLI tools

Changelogs document intent. Behavioral diffs document reality.

## What to Check

### 1. Install Scripts

Check `package.json` scripts (npm) or `setup.py`/`pyproject.toml` (Python)
for `preinstall`, `postinstall`, `prepare` hooks.

```bash
# npm: compare scripts between versions
diff <(npm show <pkg>@<old> scripts --json) <(npm show <pkg>@<new> scripts --json)

# Check for lifecycle scripts in the new version
npm show <pkg>@<new> scripts --json | grep -E "pre|post|prepare|install"
```

**Red flag:** New install script that didn't exist before. Especially
`postinstall` that fetches remote resources or runs binaries.

### 2. Network Calls

Search the package diff for new outbound connections (HTTP clients, fetch
calls, socket operations) in production code — not tests.

**Red flag:** Production code that contacts domains not present in the
previous version.

### 3. Filesystem Access

Search for new file operations outside the package's own directory,
especially reads of credential files or writes outside the project tree.

**Red flag:** Accessing `~/.ssh`, `~/.aws`, or writing outside
`node_modules` / the project directory.

### 4. Removed Exports

Compare the public API surface between versions:

```bash
# npm: compare exports
diff <(npm show <pkg>@<old> exports --json) <(npm show <pkg>@<new> exports --json)

# Or compare the main entry point's exports
```

**Red flag:** Removed export that your codebase imports. This is a
breaking change regardless of semver classification.

### 5. Native Dependencies

Check for new native/binary compilation requirements (`node-gyp`, C
extensions, `build.rs`, CGo) that would break pure-script environments.

**Red flag:** Pure-JS/Python package adding a native dependency. Breaks
CI, Docker alpine, and cross-platform builds.

### 6. Permission Escalation

For CLI tools and packages with elevated privileges, check for new
`sudo`, `chmod`, `chown` usage or broader permission requests.

**Red flag:** Package requesting more permissions than before without
clear justification.

## Risk Classification

| Risk | Criteria | Example |
|------|----------|---------|
| **Critical** | New install script with network/fs access, known supply chain attack patterns | `postinstall` that downloads and executes a remote binary |
| **High** | Removed exports your code uses, new native deps, new network calls in prod code | Package starts phoning home to telemetry endpoint |
| **Medium** | New filesystem access (scoped), significant API changes, new optional deps | Writes cache files to `~/.cache/<pkg>/` |
| **Low** | New devDependencies, documentation changes, test-only changes | Added `prettier` as devDep |

## Analysis Protocol

For each package being upgraded:

1. **Read the diff** between old and new version. For npm:
   `npm diff --diff=<pkg>@<old> --diff=<pkg>@<new>`. Focus on non-test
   source files.

2. **Check install scripts** — any new or modified lifecycle hooks?

3. **Search for behavioral additions** — new network, fs, or process
   operations in production code?

4. **Compare exports** — anything removed or renamed?

5. **Check for native deps** — any new binary/compilation requirements?

6. **Classify risk** — use the table above.

## Output Format

For each package analyzed:

```markdown
### <package> <old> → <new>

**Risk:** Low | Medium | High | Critical
**Install scripts:** None | Unchanged | NEW (details)
**Network changes:** None | New endpoint: `api.example.com`
**Filesystem changes:** None | New: writes to `~/.cache/pkg/`
**Export changes:** None | Removed: `legacyFunction`
**Native deps:** None | New: requires `node-gyp`
**Summary:** [One sentence: safe to upgrade / needs review / block upgrade]
```

## When to Block an Upgrade

- New `postinstall` script with network or filesystem access
- Removed export that the project actively uses
- New native dependency without clear justification
- Any pattern matching known supply-chain attack vectors (typosquatting,
  obfuscated code, base64-encoded payloads in install scripts)

When blocking: document the reason, pin the current version explicitly,
and create a follow-up issue to investigate.
