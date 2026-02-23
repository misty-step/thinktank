// internal/fileutil/filtering_test.go
package fileutil

import (
	"os"
	"path/filepath"
	"testing"
)

func TestShouldProcess(t *testing.T) {
	// This test uses the real isGitIgnored function,
	// so it might behave differently depending on git being installed

	tests := []struct {
		name         string
		path         string
		config       *Config
		expected     bool
		setupFunc    func(*Config)
		cleanupFunc  func()
		checkLogging func(*testing.T, *MockLogger)
	}{
		// Basic cases
		{
			name:     "Simple file, no filters",
			path:     "test.txt",
			expected: true,
			setupFunc: func(c *Config) {
				// No filters to set up
			},
		},
		{
			name:     "Excluded by extension",
			path:     "test.exe",
			expected: false,
			setupFunc: func(c *Config) {
				c.ExcludeExts = []string{".exe", ".bin"}
			},
			checkLogging: func(t *testing.T, l *MockLogger) {
				if !l.ContainsMessage("Skipping excluded extension") {
					t.Errorf("Expected log about excluded extension")
				}
			},
		},
		{
			name:     "Explicitly included extension",
			path:     "test.go",
			expected: true,
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go", ".md"}
			},
		},
		{
			name:     "Not in include list",
			path:     "test.js",
			expected: false,
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go", ".md"}
			},
			checkLogging: func(t *testing.T, l *MockLogger) {
				if !l.ContainsMessage("Skipping non-included extension") {
					t.Errorf("Expected log about non-included extension")
				}
			},
		},
		{
			name:     "Excluded by name",
			path:     "node_modules",
			expected: false,
			setupFunc: func(c *Config) {
				c.ExcludeNames = []string{"node_modules", "dist"}
			},
			checkLogging: func(t *testing.T, l *MockLogger) {
				if !l.ContainsMessage("Skipping excluded name") {
					t.Errorf("Expected log about excluded name")
				}
			},
		},
		{
			name:     "Hidden file",
			path:     ".gitignore",
			expected: false,
			setupFunc: func(c *Config) {
				// No special setup needed for hidden files
			},
		},
		{
			name:     "Complex filters - should process",
			path:     "src/main.go",
			expected: true,
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go", ".md"}
				c.ExcludeExts = []string{".exe", ".bin"}
			},
		},

		// Additional test cases for improved coverage
		{
			name:     "File in .git directory",
			path:     ".git/config",
			expected: true, // The implementation only checks .git at the very start of the path or as a directory in a path
			setupFunc: func(c *Config) {
				// No special setup needed
			},
		},
		{
			name:     "File with mixed case extension - excluded",
			path:     "test.EXE",
			expected: false,
			setupFunc: func(c *Config) {
				c.ExcludeExts = []string{".exe"}
			},
			checkLogging: func(t *testing.T, l *MockLogger) {
				if !l.ContainsMessage("Skipping excluded extension") {
					t.Errorf("Expected log about excluded extension")
				}
			},
		},
		{
			name:     "File with mixed case extension - included",
			path:     "test.GO",
			expected: true,
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go"}
			},
		},
		{
			name:     "File with no extension - no filters",
			path:     "Makefile",
			expected: true,
			setupFunc: func(c *Config) {
				// No filters
			},
		},
		{
			name:     "File with no extension - include filter",
			path:     "Makefile",
			expected: false,
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go", ".md"}
			},
			checkLogging: func(t *testing.T, l *MockLogger) {
				if !l.ContainsMessage("Skipping non-included extension") {
					t.Errorf("Expected log about non-included extension")
				}
			},
		},
		{
			name:     "Path with directory containing excluded name",
			path:     "src/node_modules/somefile.js",
			expected: true, // Should process because only the base name is checked
			setupFunc: func(c *Config) {
				c.ExcludeNames = []string{"node_modules"}
			},
		},
		{
			name:     "Multiple conditions: included extension but excluded name",
			path:     "node_modules/test.go",
			expected: true, // The implementation only checks base name against ExcludeNames, not directory components
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go"}
				c.ExcludeNames = []string{"node_modules"}
			},
		},
		{
			name:     "Multiple conditions: included extension but also in exclude extensions",
			path:     "test.go",
			expected: false, // Exclude takes precedence
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go", ".md"}
				c.ExcludeExts = []string{".go", ".bin"} // Conflicting configuration
			},
			checkLogging: func(t *testing.T, l *MockLogger) {
				if !l.ContainsMessage("Skipping excluded extension") {
					t.Errorf("Expected log about excluded extension")
				}
			},
		},
		{
			name:     "Complex path with nested directories",
			path:     "src/app/utils/helpers/string.go",
			expected: true,
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go"}
			},
		},
		{
			name:     "Empty file path",
			path:     "",
			expected: false, // Empty paths are treated as having no extension, so they don't match when IncludeExts is set
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go"}
			},
			checkLogging: func(t *testing.T, l *MockLogger) {
				if !l.ContainsMessage("Skipping non-included extension") {
					t.Errorf("Expected log about non-included extension")
				}
			},
		},
		{
			name:     "Path with unusual characters",
			path:     "file with spaces.go",
			expected: true,
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go"}
			},
		},
		{
			name:     "Include and exclude empty but ExcludeNames populated",
			path:     "test.txt",
			expected: true,
			setupFunc: func(c *Config) {
				c.ExcludeNames = []string{"node_modules", "dist"}
			},
		},
		{
			name:     "Both include and exclude have same extension",
			path:     "test.go",
			expected: false, // Exclude takes precedence over include
			setupFunc: func(c *Config) {
				c.IncludeExts = []string{".go", ".md"}
				c.ExcludeExts = []string{".go"} // Conflicts with include
			},
			checkLogging: func(t *testing.T, l *MockLogger) {
				if !l.ContainsMessage("Skipping excluded extension") {
					t.Errorf("Expected log about excluded extension")
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Set up a mock logger to capture logs
			logger := NewMockLogger()
			logger.SetVerbose(true)

			// Create a config
			config := &Config{
				Logger: logger,
			}

			// Apply any test-specific setup
			if tt.setupFunc != nil {
				tt.setupFunc(config)
			}

			// Clean up after the test
			if tt.cleanupFunc != nil {
				defer tt.cleanupFunc()
			}

			// Run the test
			result := shouldProcess(tt.path, config)

			// Check the result
			if result != tt.expected {
				t.Errorf("shouldProcess(%q) = %v, want %v", tt.path, result, tt.expected)
			}

			// Check logs if needed
			if tt.checkLogging != nil {
				tt.checkLogging(t, logger)
			}
		})
	}
}

func TestFilterFiles(t *testing.T) {
	tests := []struct {
		name     string
		paths    []string
		opts     FilteringOptions
		expected []string
	}{
		{
			name:     "no filters - all files pass",
			paths:    []string{"main.go", "test.py", "readme.md"},
			opts:     FilteringOptions{},
			expected: []string{"main.go", "test.py", "readme.md"},
		},
		{
			name:  "include extensions filter",
			paths: []string{"main.go", "test.py", "readme.md", "config.json"},
			opts: FilteringOptions{
				IncludeExts: []string{".go", ".py"},
			},
			expected: []string{"main.go", "test.py"},
		},
		{
			name:  "exclude extensions filter",
			paths: []string{"main.go", "test.py", "readme.md", "binary.exe"},
			opts: FilteringOptions{
				ExcludeExts: []string{".exe", ".md"},
			},
			expected: []string{"main.go", "test.py"},
		},
		{
			name:  "exclude names filter",
			paths: []string{"main.go", "node_modules", "test.py", ".env"},
			opts: FilteringOptions{
				ExcludeNames: []string{"node_modules", ".env"},
			},
			expected: []string{"main.go", "test.py"},
		},
		{
			name:  "ignore hidden files",
			paths: []string{"main.go", ".hidden", "test.py", ".git/config"},
			opts: FilteringOptions{
				IgnoreHidden: true,
			},
			expected: []string{"main.go", "test.py"},
		},
		{
			name:  "ignore git files",
			paths: []string{"main.go", ".gitignore", "test.py", ".git/HEAD"},
			opts: FilteringOptions{
				IgnoreGitFiles: true,
			},
			expected: []string{"main.go", "test.py"},
		},
		{
			name:  "complex filtering",
			paths: []string{"main.go", "test.py", ".hidden.go", "readme.md", "node_modules", ".gitignore"},
			opts: FilteringOptions{
				IncludeExts:    []string{".go", ".py"},
				ExcludeNames:   []string{"node_modules"},
				IgnoreHidden:   true,
				IgnoreGitFiles: true,
			},
			expected: []string{"main.go", "test.py"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := FilterFiles(tt.paths, tt.opts)
			if len(result) != len(tt.expected) {
				t.Errorf("FilterFiles() length = %d, want %d", len(result), len(tt.expected))
				t.Errorf("FilterFiles() = %v, want %v", result, tt.expected)
				return
			}

			// Check each expected file is in the result
			for _, expected := range tt.expected {
				found := false
				for _, actual := range result {
					if actual == expected {
						found = true
						break
					}
				}
				if !found {
					t.Errorf("FilterFiles() missing expected file %q in result %v", expected, result)
				}
			}
		})
	}
}

func TestShouldProcessFilePure(t *testing.T) {
	tests := []struct {
		name             string
		path             string
		opts             FilteringOptions
		expectedProcess  bool
		expectedReason   string
		expectedFileType string
	}{
		{
			name:             "simple go file",
			path:             "main.go",
			opts:             FilteringOptions{},
			expectedProcess:  true,
			expectedReason:   "passed all filters",
			expectedFileType: "go",
		},
		{
			name: "excluded extension",
			path: "binary.exe",
			opts: FilteringOptions{
				ExcludeExts: []string{".exe"},
			},
			expectedProcess:  false,
			expectedReason:   "extension in exclude list",
			expectedFileType: "other",
		},
		{
			name: "not in include list",
			path: "readme.md",
			opts: FilteringOptions{
				IncludeExts: []string{".go", ".py"},
			},
			expectedProcess:  false,
			expectedReason:   "extension not in include list",
			expectedFileType: "markdown",
		},
		{
			name: "excluded by name",
			path: "node_modules",
			opts: FilteringOptions{
				ExcludeNames: []string{"node_modules", "vendor"},
			},
			expectedProcess:  false,
			expectedReason:   "excluded by name",
			expectedFileType: "no_extension",
		},
		{
			name: "hidden file",
			path: ".hidden",
			opts: FilteringOptions{
				IgnoreHidden: true,
			},
			expectedProcess:  false,
			expectedReason:   "hidden file or directory",
			expectedFileType: "other", // .hidden is treated as an extension by filepath.Ext
		},
		{
			name: "git file",
			path: ".gitignore",
			opts: FilteringOptions{
				IgnoreGitFiles: true,
			},
			expectedProcess:  false,
			expectedReason:   "git-related file",
			expectedFileType: "other", // .gitignore is treated as an extension by filepath.Ext
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ShouldProcessFile(tt.path, tt.opts)

			if result.ShouldProcess != tt.expectedProcess {
				t.Errorf("ShouldProcessFile().ShouldProcess = %v, want %v", result.ShouldProcess, tt.expectedProcess)
			}

			if result.Reason != tt.expectedReason {
				t.Errorf("ShouldProcessFile().Reason = %q, want %q", result.Reason, tt.expectedReason)
			}

			if result.FileType != tt.expectedFileType {
				t.Errorf("ShouldProcessFile().FileType = %q, want %q", result.FileType, tt.expectedFileType)
			}
		})
	}
}

func TestCalculateFileStatistics(t *testing.T) {
	tests := []struct {
		name     string
		content  string
		expected FileStatistics
	}{
		{
			name:    "empty content",
			content: "",
			expected: FileStatistics{
				CharCount:         0,
				LineCount:         0,
				WordCount:         0,
				TokenCount:        0,
				BlankLineCount:    0,
				NonBlankLines:     0,
				AverageLineLength: 0,
			},
		},
		{
			name:    "single line",
			content: "hello world",
			expected: FileStatistics{
				CharCount:         11,
				LineCount:         1,
				WordCount:         2,
				TokenCount:        2,
				BlankLineCount:    0,
				NonBlankLines:     1,
				AverageLineLength: 11.0,
			},
		},
		{
			name:    "multiple lines with blank line",
			content: "line 1\n\nline 3",
			expected: FileStatistics{
				CharCount:      14, // "line 1" (6) + "\n" (1) + "\n" (1) + "line 3" (6) = 14
				LineCount:      3,
				WordCount:      4,
				BlankLineCount: 1,
				NonBlankLines:  2,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := CalculateFileStatistics(tt.content)

			if result.CharCount != tt.expected.CharCount {
				t.Errorf("CharCount = %d, want %d", result.CharCount, tt.expected.CharCount)
			}

			if result.LineCount != tt.expected.LineCount {
				t.Errorf("LineCount = %d, want %d", result.LineCount, tt.expected.LineCount)
			}

			if result.WordCount != tt.expected.WordCount {
				t.Errorf("WordCount = %d, want %d", result.WordCount, tt.expected.WordCount)
			}

			if result.BlankLineCount != tt.expected.BlankLineCount {
				t.Errorf("BlankLineCount = %d, want %d", result.BlankLineCount, tt.expected.BlankLineCount)
			}

			if result.NonBlankLines != tt.expected.NonBlankLines {
				t.Errorf("NonBlankLines = %d, want %d", result.NonBlankLines, tt.expected.NonBlankLines)
			}

			// Token count should be at least as many as words
			if result.TokenCount < result.WordCount {
				t.Errorf("TokenCount = %d should be at least as many as WordCount = %d", result.TokenCount, result.WordCount)
			}
		})
	}
}

// TestIOOperations tests the extracted I/O functions
func TestIOOperations(t *testing.T) {
	// Create a temporary directory for testing
	tempDir := t.TempDir()

	// Create test files
	testFile := filepath.Join(tempDir, "test.txt")
	testContent := []byte("Hello, World!\nThis is a test file.")

	err := os.WriteFile(testFile, testContent, 0644)
	if err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	// Create test directory
	testSubDir := filepath.Join(tempDir, "subdir")
	err = os.Mkdir(testSubDir, 0755)
	if err != nil {
		t.Fatalf("Failed to create test directory: %v", err)
	}

	t.Run("ReadFileContent", func(t *testing.T) {
		content, err := ReadFileContent(testFile)
		if err != nil {
			t.Errorf("ReadFileContent() error = %v", err)
			return
		}

		if string(content) != string(testContent) {
			t.Errorf("ReadFileContent() = %q, want %q", string(content), string(testContent))
		}

		// Test non-existent file
		_, err = ReadFileContent(filepath.Join(tempDir, "nonexistent.txt"))
		if err == nil {
			t.Error("ReadFileContent() should return error for non-existent file")
		}
	})

	t.Run("StatPath", func(t *testing.T) {
		// Test file
		info, err := StatPath(testFile)
		if err != nil {
			t.Errorf("StatPath() error = %v", err)
			return
		}

		if info.IsDir() {
			t.Error("StatPath() should return file info, not directory info")
		}

		if info.Size() != int64(len(testContent)) {
			t.Errorf("StatPath() size = %d, want %d", info.Size(), len(testContent))
		}

		// Test directory
		info, err = StatPath(testSubDir)
		if err != nil {
			t.Errorf("StatPath() error = %v", err)
			return
		}

		if !info.IsDir() {
			t.Error("StatPath() should return directory info")
		}

		// Test non-existent path
		_, err = StatPath(filepath.Join(tempDir, "nonexistent"))
		if err == nil {
			t.Error("StatPath() should return error for non-existent path")
		}
	})

	t.Run("WalkDirectory", func(t *testing.T) {
		var visitedPaths []string

		err := WalkDirectory(tempDir, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			visitedPaths = append(visitedPaths, path)
			return nil
		})

		if err != nil {
			t.Errorf("WalkDirectory() error = %v", err)
			return
		}

		// Should visit at least the root directory, test file, and subdirectory
		if len(visitedPaths) < 3 {
			t.Errorf("WalkDirectory() visited %d paths, want at least 3", len(visitedPaths))
		}

		// Check that our test file was visited
		found := false
		for _, path := range visitedPaths {
			if path == testFile {
				found = true
				break
			}
		}
		if !found {
			t.Error("WalkDirectory() did not visit test file")
		}
	})

	t.Run("GetAbsolutePath", func(t *testing.T) {
		// Test with relative path
		absPath, err := GetAbsolutePath(".")
		if err != nil {
			t.Errorf("GetAbsolutePath() error = %v", err)
			return
		}

		if !filepath.IsAbs(absPath) {
			t.Errorf("GetAbsolutePath() = %q, should be absolute", absPath)
		}

		// Test with already absolute path
		abs2, err := GetAbsolutePath(absPath)
		if err != nil {
			t.Errorf("GetAbsolutePath() error = %v", err)
			return
		}

		if abs2 != absPath {
			t.Errorf("GetAbsolutePath() = %q, want %q", abs2, absPath)
		}
	})

	t.Run("CheckGitRepo", func(t *testing.T) {
		// Test with non-git directory
		isGitRepo := CheckGitRepo(tempDir)
		if isGitRepo {
			t.Error("CheckGitRepo() should return false for non-git directory")
		}

		// Test with current project directory (which should be a git repo)
		currentDir, _ := os.Getwd()
		_ = CheckGitRepo(currentDir)
		// This test is environment-dependent, so we don't assert the result
		// but just make sure it doesn't panic
	})

	t.Run("CheckGitIgnore", func(t *testing.T) {
		// Test with non-git directory (should return error)
		_, err := CheckGitIgnore(tempDir, "test.txt")
		if err == nil {
			t.Error("CheckGitIgnore() should return error for non-git directory")
		}

		// We don't test with actual git repo here as it would be environment-dependent
		// and might interfere with the actual project's git state
	})
}

// TestGitCheckerCachingUsage tests GitChecker caching behavior in filtering scenarios.
// Comprehensive GitChecker tests are in git_checker_test.go.
func TestGitCheckerCachingUsage(t *testing.T) {
	t.Run("IsRepo returns consistent results", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		result1 := gc.IsRepo(tempDir)
		result2 := gc.IsRepo(tempDir)

		if result1 != result2 {
			t.Errorf("IsRepo returned inconsistent results: %v vs %v", result1, result2)
		}
	})

	t.Run("IsIgnored returns false for non-git directory", func(t *testing.T) {
		gc := NewGitChecker()
		tempDir := t.TempDir()

		// Non-git directory: should return (false, nil), not an error
		// because GitChecker.IsIgnored checks IsRepo first
		isIgnored, err := gc.IsIgnored(tempDir, "test.txt")

		if err != nil {
			t.Errorf("Unexpected error for non-git directory: %v", err)
		}
		if isIgnored {
			t.Error("Should return false for non-git directory")
		}
	})

	t.Run("NewGitChecker creates isolated cache state", func(t *testing.T) {
		tempDir := t.TempDir()
		gc1 := NewGitChecker()

		// Populate cache
		_ = gc1.IsRepo(tempDir)
		if gc1.CacheStats() != 1 {
			t.Errorf("Expected gc1 to have 1 cache entry, got %d", gc1.CacheStats())
		}

		// New checker should have independent empty cache
		gc2 := NewGitChecker()
		if gc2.CacheStats() != 0 {
			t.Errorf("Expected gc2 to start with empty cache, got %d", gc2.CacheStats())
		}
	})
}

func TestValidateFilePath(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		wantValid  bool
		wantResult string
	}{
		{
			name:       "valid absolute path",
			path:       "/tmp/output/file.txt",
			wantValid:  true,
			wantResult: "/tmp/output/file.txt",
		},
		{
			name:       "valid relative path",
			path:       "output/file.txt",
			wantValid:  true,
			wantResult: "output/file.txt",
		},
		{
			name:       "path with ./",
			path:       "./output/file.txt",
			wantValid:  true,
			wantResult: "output/file.txt", // filepath.Clean removes ./
		},
		{
			name:       "path normalization with .. that stays within dir",
			path:       "./test/../main.go",
			wantValid:  true,
			wantResult: "main.go", // normalizes to valid path
		},
		{
			name:       "absolute path with .. that resolves cleanly",
			path:       "/tmp/foo/../bar/file.txt",
			wantValid:  true,
			wantResult: "/tmp/bar/file.txt", // resolves without escaping
		},
		{
			name:      "empty path",
			path:      "",
			wantValid: false,
		},
		{
			name:      "path traversal - escapes upward",
			path:      "../../../etc/passwd",
			wantValid: false,
		},
		{
			name:      "path traversal - just double dot",
			path:      "..",
			wantValid: false,
		},
		{
			name:      "path traversal - starts with ..",
			path:      "../file.txt",
			wantValid: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, valid := ValidateFilePath(tt.path)
			if valid != tt.wantValid {
				t.Errorf("ValidateFilePath(%q) valid = %v, want %v", tt.path, valid, tt.wantValid)
			}
			if tt.wantValid && result != tt.wantResult {
				t.Errorf("ValidateFilePath(%q) result = %q, want %q", tt.path, result, tt.wantResult)
			}
		})
	}
}

func TestValidateOutputPath(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		wantValid  bool
		wantResult string
	}{
		{
			name:       "valid absolute path",
			path:       "/tmp/output/file.txt",
			wantValid:  true,
			wantResult: "/tmp/output/file.txt",
		},
		{
			name:       "valid relative path",
			path:       "output/file.txt",
			wantValid:  true,
			wantResult: "output/file.txt",
		},
		{
			name:       "path with ./",
			path:       "./output/file.txt",
			wantValid:  true,
			wantResult: "output/file.txt",
		},
		{
			name:      "empty path",
			path:      "",
			wantValid: false,
		},
		{
			name:      "path traversal - simple",
			path:      "../../../etc/passwd",
			wantValid: false,
		},
		{
			name:      "path traversal - absolute with ..",
			path:      "/tmp/foo/../../../etc/passwd",
			wantValid: false,
		},
		{
			name:      "path traversal - hidden in middle (strict rejection)",
			path:      "/tmp/foo/../bar/file.txt",
			wantValid: false, // Stricter than ValidateFilePath - rejects any ..
		},
		{
			name:      "path traversal - normalization with .. (strict rejection)",
			path:      "./test/../main.go",
			wantValid: false, // Stricter than ValidateFilePath - rejects any ..
		},
		{
			name:      "path traversal - just double dot",
			path:      "..",
			wantValid: false,
		},
		{
			name:      "path traversal - starts with ..",
			path:      "../file.txt",
			wantValid: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, valid := ValidateOutputPath(tt.path)
			if valid != tt.wantValid {
				t.Errorf("ValidateOutputPath(%q) valid = %v, want %v", tt.path, valid, tt.wantValid)
			}
			if tt.wantValid && result != tt.wantResult {
				t.Errorf("ValidateOutputPath(%q) result = %q, want %q", tt.path, result, tt.wantResult)
			}
		})
	}
}
