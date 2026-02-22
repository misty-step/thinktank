package fileutil

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
)

// TestGitCheckerIsRepo tests the IsRepo method with various scenarios.
func TestGitCheckerIsRepo(t *testing.T) {
	t.Run("non-git directory returns false", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		result := gc.IsRepo(tempDir)

		if result {
			t.Error("IsRepo() should return false for non-git directory")
		}
	})

	t.Run("current directory (git repo) returns true", func(t *testing.T) {
		gc := NewGitChecker()
		currentDir, err := os.Getwd()
		if err != nil {
			t.Skip("Could not get current directory")
		}

		result := gc.IsRepo(currentDir)

		// This test assumes we're running from within a git repo
		if !result {
			t.Skip("Not running from within a git repo")
		}
	})

	t.Run("caches results for same directory", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		// First call
		result1 := gc.IsRepo(tempDir)
		// Second call should hit cache
		result2 := gc.IsRepo(tempDir)

		if result1 != result2 {
			t.Errorf("IsRepo returned inconsistent results: %v vs %v", result1, result2)
		}

		// Verify cache was populated
		if gc.CacheStats() != 1 {
			t.Errorf("Expected 1 cache entry, got %d", gc.CacheStats())
		}
	})

	t.Run("normalizes paths to absolute for cache keys", func(t *testing.T) {
		gc := NewGitChecker()

		// Get current directory as both relative and absolute
		currentDir, err := os.Getwd()
		if err != nil {
			t.Skip("Could not get current directory")
		}

		// Query with relative path
		_ = gc.IsRepo(".")
		// Query with absolute path
		_ = gc.IsRepo(currentDir)

		// Both should have been normalized to the same cache key
		// So we should have exactly 1 cache entry
		if gc.CacheStats() != 1 {
			t.Errorf("Expected 1 cache entry (paths normalized), got %d", gc.CacheStats())
		}
	})

	t.Run("handles path with trailing slash", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		// Query with and without trailing slash
		result1 := gc.IsRepo(tempDir)
		result2 := gc.IsRepo(tempDir + "/")

		if result1 != result2 {
			t.Errorf("Results differ for trailing slash: %v vs %v", result1, result2)
		}
	})

	t.Run("handles path with dots", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		// Create a subdirectory to test ".." navigation
		subDir := filepath.Join(tempDir, "subdir")
		if err := os.Mkdir(subDir, 0755); err != nil {
			t.Fatal(err)
		}

		// Query both the original and the path with ..
		result1 := gc.IsRepo(tempDir)
		result2 := gc.IsRepo(filepath.Join(subDir, ".."))

		if result1 != result2 {
			t.Errorf("Results differ for '..' path: %v vs %v", result1, result2)
		}

		// Should normalize to same key
		if gc.CacheStats() != 1 {
			t.Errorf("Expected 1 cache entry (.. normalized), got %d", gc.CacheStats())
		}
	})
}

// TestGitCheckerIsIgnored tests the IsIgnored method.
func TestGitCheckerIsIgnored(t *testing.T) {
	t.Run("returns false for non-git directory", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		isIgnored, err := gc.IsIgnored(tempDir, "test.txt")

		if err != nil {
			t.Errorf("IsIgnored() returned unexpected error: %v", err)
		}
		if isIgnored {
			t.Error("IsIgnored() should return false for non-git directory")
		}
	})

	t.Run("checks ignore status in git repo", func(t *testing.T) {
		gc := NewGitChecker()
		currentDir, err := os.Getwd()
		if err != nil {
			t.Skip("Could not get current directory")
		}

		if !gc.IsRepo(currentDir) {
			t.Skip("Not in a git repo")
		}

		// go.mod should not be ignored
		isIgnored, err := gc.IsIgnored(currentDir, "go.mod")
		if err != nil {
			t.Errorf("IsIgnored() error for go.mod: %v", err)
		}
		if isIgnored {
			t.Error("go.mod should not be ignored in a typical Go project")
		}
	})
}

// TestGitCheckerConcurrency tests thread safety.
func TestGitCheckerConcurrency(t *testing.T) {
	t.Run("concurrent IsRepo calls are safe", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		var wg sync.WaitGroup
		results := make(chan bool, 100)

		// Launch 100 concurrent goroutines
		for i := 0; i < 100; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				results <- gc.IsRepo(tempDir)
			}()
		}

		wg.Wait()
		close(results)

		// All results should be the same
		var first *bool
		for result := range results {
			if first == nil {
				r := result
				first = &r
			} else if result != *first {
				t.Error("Concurrent calls returned inconsistent results")
			}
		}
	})

	t.Run("concurrent mixed operations are safe", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		var wg sync.WaitGroup

		// Mix of IsRepo and IsIgnored calls
		for i := 0; i < 50; i++ {
			wg.Add(2)
			go func() {
				defer wg.Done()
				_ = gc.IsRepo(tempDir)
			}()
			go func() {
				defer wg.Done()
				_, _ = gc.IsIgnored(tempDir, "test.txt")
			}()
		}

		wg.Wait()
		// Test passes if no panic/race occurs
	})
}

// TestGitCheckerIsolation tests that each GitChecker instance is independent.
func TestGitCheckerIsolation(t *testing.T) {
	t.Run("separate instances have separate caches", func(t *testing.T) {
		gc1 := NewGitChecker()
		gc2 := NewGitChecker()
		tempDir := t.TempDir()

		// Populate gc1's cache
		_ = gc1.IsRepo(tempDir)

		if gc1.CacheStats() != 1 {
			t.Errorf("gc1 should have 1 cache entry, got %d", gc1.CacheStats())
		}

		if gc2.CacheStats() != 0 {
			t.Errorf("gc2 should have 0 cache entries, got %d", gc2.CacheStats())
		}
	})

	t.Run("test isolation with NewGitChecker", func(t *testing.T) {
		// Demonstrate that each test can get a fresh GitChecker
		// without needing a shared cache reset helper
		gc := NewGitChecker()

		if gc.CacheStats() != 0 {
			t.Errorf("New GitChecker should have empty cache, got %d entries", gc.CacheStats())
		}
	})
}

// TestGitCheckerCacheStats tests the CacheStats diagnostic method.
func TestGitCheckerCacheStats(t *testing.T) {
	gc := NewGitChecker()

	if gc.CacheStats() != 0 {
		t.Errorf("New GitChecker should have 0 entries, got %d", gc.CacheStats())
	}

	// Add some entries
	tempDir1 := t.TempDir()
	tempDir2 := t.TempDir()

	_ = gc.IsRepo(tempDir1)
	_ = gc.IsRepo(tempDir2)

	if gc.CacheStats() != 2 {
		t.Errorf("Expected 2 entries, got %d", gc.CacheStats())
	}
}

// TestGitCheckerUsagePatterns tests common GitChecker usage patterns.
func TestGitCheckerUsagePatterns(t *testing.T) {
	t.Run("IsRepo works", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		result := gc.IsRepo(tempDir)

		if result {
			t.Error("IsRepo should return false for non-git dir")
		}
	})

	t.Run("IsIgnored works", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		_, err := gc.IsIgnored(tempDir, "test.txt")

		// Should not return error (just returns false for non-git dir)
		if err != nil {
			t.Errorf("IsIgnored unexpected error: %v", err)
		}
	})

	t.Run("NewGitChecker starts with empty cache", func(t *testing.T) {
		tempDir := t.TempDir()

		// Populate cache
		gc1 := NewGitChecker()
		_ = gc1.IsRepo(tempDir)

		// A new checker has isolated cache state
		gc2 := NewGitChecker()
		if gc2.CacheStats() != 0 {
			t.Errorf("New GitChecker cache should be empty, got %d", gc2.CacheStats())
		}
	})
}

// TestNestedGitRepos tests handling of nested directories within a git repository.
func TestNestedGitRepos(t *testing.T) {
	gc := NewGitChecker()

	// Get current directory (where tests run from)
	currentDir, err := os.Getwd()
	if err != nil {
		t.Skip("Could not get current directory")
	}

	if !gc.IsRepo(currentDir) {
		t.Skip("Not in a git repo")
	}

	// Create a temp subdirectory within the current directory
	// This simulates a nested directory within a git repo
	subDir := filepath.Join(currentDir, "test_nested_subdir")
	if err := os.Mkdir(subDir, 0755); err != nil {
		t.Fatalf("Failed to create test subdirectory: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(subDir) })

	// The subdirectory should also be detected as part of the git repo
	result := gc.IsRepo(subDir)

	if !result {
		t.Error("Nested directory should be detected as part of git repo")
	}

	// Each directory should be cached separately
	_ = gc.IsRepo(currentDir)
	_ = gc.IsRepo(subDir)

	// Verify we have 2 cache entries (they're different directories)
	if gc.CacheStats() < 2 {
		t.Errorf("Expected at least 2 cache entries, got %d", gc.CacheStats())
	}
}
