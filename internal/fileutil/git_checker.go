// Package fileutil provides file system utilities for project context gathering.
package fileutil

import (
	"os/exec"
	"path/filepath"
	"sync"
)

// GitChecker provides cached git repository detection.
//
// This is a deep module following Ousterhout's principles:
//   - Simple interface: IsRepo(dir) returns bool
//   - Rich implementation: caching, path normalization, subprocess management
//   - Information hiding: callers don't know about or manage the cache
//
// Cache semantics:
//   - Keys: absolute paths (via filepath.Abs) for canonical representation
//   - Values: bool indicating whether directory is inside a git repository
//   - Lifetime: bound to GitChecker instance lifetime
//   - Size: O(unique directories checked) - bounded by filesystem depth
//   - Thread-safety: sync.Map provides concurrent read/write access
//
// Design rationale:
//   - Caching CheckGitRepo is effective: many files share the same directory,
//     so O(files) calls become O(directories) calls
//   - Caching CheckGitIgnore is NOT effective for single-pass file walks:
//     each filename is unique, resulting in 0% cache hit rate. Therefore,
//     git ignore checks are not cached.
type GitChecker struct {
	repoCache sync.Map // absolute dir path -> isRepo (bool)
}

// NewGitChecker creates a new GitChecker instance.
// Each instance has its own cache, providing natural test isolation.
func NewGitChecker() *GitChecker {
	return &GitChecker{}
}

// IsRepo checks if a directory is inside a git repository.
// Results are cached by absolute path for the lifetime of this GitChecker.
//
// This method is safe for concurrent use.
func (gc *GitChecker) IsRepo(dir string) bool {
	// Normalize to absolute path for canonical cache keys.
	// This ensures "." and "/absolute/path/to/cwd" hit the same cache entry.
	absDir, err := filepath.Abs(dir)
	if err != nil {
		// If we can't get absolute path, fall back to uncached check.
		// This is rare (invalid path) and correctness > performance.
		return checkGitRepoUncached(dir)
	}

	// Check cache first
	if cached, ok := gc.repoCache.Load(absDir); ok {
		return cached.(bool)
	}

	// Cache miss: perform the actual check
	result := checkGitRepoUncached(absDir)

	// Store result. Note: sync.Map handles concurrent Store safely.
	// Multiple goroutines may race to store the same key, but since
	// the operation is idempotent, this is harmless (just redundant work).
	gc.repoCache.Store(absDir, result)

	return result
}

// IsIgnored checks if a file is ignored by git in the given directory.
// This method does NOT cache results because:
//   - In single-pass file walks, each filename is unique (0% hit rate)
//   - Caching would add O(files) memory overhead with no benefit
//   - The subprocess cost is unavoidable for accurate gitignore checking
//
// For batch operations, consider using CheckGitIgnoreBatch instead.
//
// Returns:
//   - true if the file is ignored by git
//   - false if the file is not ignored OR if dir is not a git repo
//   - Error only for unexpected git failures (not "not a repo")
func (gc *GitChecker) IsIgnored(dir, filename string) (bool, error) {
	// Only check gitignore if we're in a git repo
	if !gc.IsRepo(dir) {
		return false, nil
	}
	return checkGitIgnoreUncached(dir, filename)
}

// CacheStats returns the number of cached entries for diagnostics.
// This is useful for testing and debugging.
func (gc *GitChecker) CacheStats() int {
	count := 0
	gc.repoCache.Range(func(_, _ any) bool {
		count++
		return true
	})
	return count
}

// checkGitRepoUncached performs the actual git repository detection.
// This spawns a git subprocess, which is expensive (~5ms).
func checkGitRepoUncached(dir string) bool {
	cmd := exec.Command("git", "-C", dir, "rev-parse", "--is-inside-work-tree")
	return cmd.Run() == nil
}

// checkGitIgnoreUncached checks if a file is ignored by git.
// Returns (true, nil) if ignored, (false, nil) if not ignored,
// and (false, error) for unexpected failures.
func checkGitIgnoreUncached(dir, filename string) (bool, error) {
	// Use "--" separator to prevent filenames starting with "-" from being parsed as options
	cmd := exec.Command("git", "-C", dir, "check-ignore", "-q", "--", filename)
	err := cmd.Run()
	if err == nil {
		return true, nil // Exit code 0: file IS ignored
	}
	if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
		return false, nil // Exit code 1: file is NOT ignored
	}
	return false, err // Other error
}
