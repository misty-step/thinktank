package config

import (
	"strings"
	"testing"
	"time"

	"github.com/misty-step/thinktank/internal/logutil"
)

// TestCliConfigValidationScenarios tests comprehensive CLI configuration validation scenarios
func TestCliConfigValidationScenarios(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name          string
		config        *CliConfig
		mockGetenv    func(string) string
		expectError   bool
		errorContains string
		description   string
	}{
		{
			name: "Container environment - OpenRouter model detection",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "test-key",
				ModelNames:       []string{"openrouter/deepseek/deepseek-chat"},
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "sk-or-test-key"
				}
				return ""
			},
			expectError: false,
			description: "OpenRouter model should be detected and require OpenRouter API key",
		},
		{
			name: "Container environment - Missing OpenRouter key",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "gemini-key",
				ModelNames:       []string{"openrouter/anthropic/claude-3"},
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "" // Missing
				}
				return "some-other-key"
			},
			expectError:   true,
			errorContains: "please set OPENROUTER_API_KEY",
			description:   "OpenRouter models should fail when OpenRouter API key is missing",
		},
		{
			name: "Multi-provider configuration",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "gemini-key",
				ModelNames:       []string{"gemini-1.5-pro", "gpt-4", "openrouter/deepseek/deepseek-chat"},
			},
			mockGetenv: func(key string) string {
				switch key {
				case "OPENAI_API_KEY":
					return "sk-openai-key"
				case OpenRouterAPIKeyEnvVar:
					return "sk-or-openrouter-key"
				default:
					return ""
				}
			},
			expectError: false,
			description: "Multiple providers should work when all required API keys are present",
		},
		{
			name: "Multi-provider configuration - partial keys",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "gemini-key",
				ModelNames:       []string{"gemini-1.5-pro", "gpt-4", "openrouter/deepseek/deepseek-chat"},
			},
			mockGetenv: func(key string) string {
				switch key {
				case "OPENAI_API_KEY":
					return "sk-openai-key"
				case OpenRouterAPIKeyEnvVar:
					return "" // Missing OpenRouter key
				default:
					return ""
				}
			},
			expectError:   true,
			errorContains: "please set OPENROUTER_API_KEY",
			description:   "Multi-provider should fail when any required API key is missing",
		},
		{
			name: "Edge case - Model name with OpenAI-like prefix but custom",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "",
				ModelNames:       []string{"gpt-custom-model"},
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "sk-openrouter-key"
				}
				return ""
			},
			expectError: false,
			description: "Models with custom names should work with OpenRouter API key",
		},
		{
			name: "Synthesis model configuration",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "",
				ModelNames:       []string{"gemini-3-flash"},
				SynthesisModel:   "gpt-5.2",
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "sk-openrouter-key"
				}
				return ""
			},
			expectError: false,
			description: "Synthesis model should be validated along with regular models",
		},
		{
			name: "Synthesis model missing API key",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "",
				ModelNames:       []string{"gemini-3-flash"},
				SynthesisModel:   "gpt-5.2",
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "" // Missing OpenRouter key for synthesis
				}
				return ""
			},
			expectError:   true,
			errorContains: "please set OPENROUTER_API_KEY",
			description:   "Synthesis model should fail when OpenRouter API key is missing",
		},
		{
			name: "Rate limiting edge values",
			config: &CliConfig{
				InstructionsFile:           "instructions.md",
				Paths:                      []string{"testfile"},
				APIKey:                     "",
				ModelNames:                 []string{"gemini-3-flash"},
				MaxConcurrentRequests:      1000,
				RateLimitRequestsPerMinute: 10000,
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "sk-openrouter-key"
				}
				return ""
			},
			expectError: false,
			description: "High rate limiting values should be acceptable",
		},
		{
			name: "Timeout configuration",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "",
				ModelNames:       []string{"gemini-3-flash"},
				Timeout:          1 * time.Hour, // Very long timeout
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "sk-openrouter-key"
				}
				return ""
			},
			expectError: false,
			description: "Long timeout values should be acceptable",
		},
		{
			name: "Complex file patterns and permissions",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"./src", "../project/lib", "/absolute/path"},
				Include:          "*.go,*.js,*.ts",
				Exclude:          "*.test.*,node_modules",
				ExcludeNames:     ".git,vendor,target",
				APIKey:           "",
				ModelNames:       []string{"gemini-3-flash"},
				DirPermissions:   0755,
				FilePermissions:  0644,
				Verbose:          true,
				DryRun:           false,
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "sk-openrouter-key"
				}
				return ""
			},
			expectError: false,
			description: "Complex file filtering and permission configurations should be valid",
		},
		{
			name: "Partial success configuration",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "",
				ModelNames:       []string{"gemini-3-flash", "gpt-5.2"},
				PartialSuccessOk: true,
			},
			mockGetenv: func(key string) string {
				// Missing OpenRouter key, but partial success is OK
				return ""
			},
			expectError:   true, // Should still fail during validation
			errorContains: "please set OPENROUTER_API_KEY",
			description:   "Partial success flag doesn't bypass validation requirements",
		},
		{
			name: "Audit logging configuration",
			config: &CliConfig{
				InstructionsFile: "instructions.md",
				Paths:            []string{"testfile"},
				APIKey:           "",
				ModelNames:       []string{"gemini-3-flash"},
				AuditLogFile:     "/var/log/thinktank-audit.jsonl",
				SplitLogs:        true,
			},
			mockGetenv: func(key string) string {
				if key == OpenRouterAPIKeyEnvVar {
					return "sk-openrouter-key"
				}
				return ""
			},
			expectError: false,
			description: "Audit logging configuration should be valid",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			logger := &MockLogger{}

			err := ValidateConfigWithEnv(tt.config, logger, tt.mockGetenv)

			// Check if error matches expectation
			if (err != nil) != tt.expectError {
				t.Errorf("ValidateConfigWithEnv() error = %v, expectError %v\nDescription: %s", err, tt.expectError, tt.description)
			}

			// Verify error contains expected text
			if tt.expectError && err != nil && tt.errorContains != "" {
				if !containsIgnoreCase(err.Error(), tt.errorContains) {
					t.Errorf("Error message %q doesn't contain expected text %q\nDescription: %s", err.Error(), tt.errorContains, tt.description)
				}
			}

			// Verify logger state
			if tt.expectError && !logger.ErrorCalled {
				t.Errorf("Expected error to be logged, but no error was logged\nDescription: %s", tt.description)
			}

			if !tt.expectError && logger.ErrorCalled {
				t.Errorf("No error expected, but error was logged: %v\nDescription: %s", logger.ErrorMessages, tt.description)
			}
		})
	}
}

// TestDefaultConfigurationRobustness tests the robustness of default configuration handling
func TestDefaultConfigurationRobustness(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name        string
		configFunc  func() interface{}
		expectPanic bool
		description string
	}{
		{
			name:        "Default CLI config multiple calls",
			configFunc:  func() interface{} { return NewDefaultCliConfig() },
			expectPanic: false,
			description: "Multiple calls to NewDefaultCliConfig should not panic",
		},
		{
			name:        "Default app config multiple calls",
			configFunc:  func() interface{} { return DefaultConfig() },
			expectPanic: false,
			description: "Multiple calls to DefaultConfig should not panic",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			defer func() {
				if r := recover(); r != nil {
					if !tt.expectPanic {
						t.Errorf("Unexpected panic: %v\nDescription: %s", r, tt.description)
					}
				} else {
					if tt.expectPanic {
						t.Errorf("Expected panic but none occurred\nDescription: %s", tt.description)
					}
				}
			}()

			// Call the function multiple times
			for i := 0; i < 10; i++ {
				result := tt.configFunc()
				if result == nil {
					t.Errorf("Configuration function returned nil on call %d\nDescription: %s", i+1, tt.description)
				}
			}
		})
	}
}

// TestConfigurationIsolation tests that configuration instances are properly isolated
func TestConfigurationIsolation(t *testing.T) {
	// Test CLI config isolation
	t.Parallel()

	config1 := NewDefaultCliConfig()
	config2 := NewDefaultCliConfig()

	// Modify config1
	config1.InstructionsFile = "modified-instructions.md"
	config1.ModelNames = append(config1.ModelNames, "added-model")
	config1.Paths = []string{"modified-path"}
	config1.Verbose = true
	config1.DryRun = true
	config1.LogLevel = logutil.DebugLevel

	// Verify config2 is unaffected
	if config2.InstructionsFile == "modified-instructions.md" {
		t.Error("Config2 InstructionsFile was affected by config1 modification")
	}

	if len(config2.ModelNames) != 1 || config2.ModelNames[0] != DefaultModel {
		t.Error("Config2 ModelNames was affected by config1 modification")
	}

	if len(config2.Paths) != 0 {
		t.Error("Config2 Paths was affected by config1 modification")
	}

	if config2.Verbose != false {
		t.Error("Config2 Verbose was affected by config1 modification")
	}

	if config2.DryRun != false {
		t.Error("Config2 DryRun was affected by config1 modification")
	}

	if config2.LogLevel != logutil.InfoLevel {
		t.Error("Config2 LogLevel was affected by config1 modification")
	}

	// Test app config isolation
	appConfig1 := DefaultConfig()
	appConfig2 := DefaultConfig()

	// Modify appConfig1
	appConfig1.OutputFile = "modified-output.md"
	appConfig1.ModelName = "modified-model"
	appConfig1.Excludes.Extensions = "modified-extensions"
	appConfig1.Excludes.Names = "modified-names"

	// Verify appConfig2 is unaffected
	if appConfig2.OutputFile != DefaultOutputFile {
		t.Error("AppConfig2 OutputFile was affected by appConfig1 modification")
	}

	if appConfig2.ModelName != DefaultModel {
		t.Error("AppConfig2 ModelName was affected by appConfig1 modification")
	}

	if appConfig2.Excludes.Extensions != DefaultExcludes {
		t.Error("AppConfig2 Excludes.Extensions was affected by appConfig1 modification")
	}

	if appConfig2.Excludes.Names != DefaultExcludeNames {
		t.Error("AppConfig2 Excludes.Names was affected by appConfig1 modification")
	}
}

// TestConfigurationEdgeCasesAndBoundaryConditions tests edge cases and boundary conditions
func TestConfigurationEdgeCasesAndBoundaryConditions(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name        string
		setupFunc   func() *CliConfig
		expectError bool
		description string
	}{
		{
			name: "Extremely long paths",
			setupFunc: func() *CliConfig {
				longPath := make([]byte, 1000)
				for i := range longPath {
					longPath[i] = 'a'
				}
				return &CliConfig{
					InstructionsFile: "instructions.md",
					Paths:            []string{string(longPath)},
					APIKey:           "test-key",
					ModelNames:       []string{"test-model"},
				}
			},
			expectError: false,
			description: "Extremely long paths should be handled gracefully",
		},
		{
			name: "Many models configuration",
			setupFunc: func() *CliConfig {
				models := make([]string, 100)
				for i := 0; i < 100; i++ {
					models[i] = "model-" + string(rune('0'+i%10))
				}
				return &CliConfig{
					InstructionsFile: "instructions.md",
					Paths:            []string{"testfile"},
					APIKey:           "test-key",
					ModelNames:       models,
				}
			},
			expectError: false,
			description: "Large number of models should be handled correctly",
		},
		{
			name: "Unicode in paths and filenames",
			setupFunc: func() *CliConfig {
				return &CliConfig{
					InstructionsFile: "指示.md",
					Paths:            []string{"测试文件", "файл.txt", "🚀file.go"},
					Include:          "*.测试,*.файл",
					APIKey:           "test-key",
					ModelNames:       []string{"test-model"},
				}
			},
			expectError: false,
			description: "Unicode characters in paths should be supported",
		},
		{
			name: "Special characters in configuration",
			setupFunc: func() *CliConfig {
				return &CliConfig{
					InstructionsFile: "instructions-with-special-chars!@#$%^&*().md",
					Paths:            []string{"/path/with spaces/and-dashes_and.dots"},
					Exclude:          "*.tmp,*.~*,*.$$$",
					ExcludeNames:     ".git,.svn,node_modules",
					APIKey:           "test-key-with-special-chars_123",
					ModelNames:       []string{"model-with-dashes_and_underscores"},
				}
			},
			expectError: false,
			description: "Special characters in configuration should be handled properly",
		},
		{
			name: "Boundary rate limiting values",
			setupFunc: func() *CliConfig {
				return &CliConfig{
					InstructionsFile:           "instructions.md",
					Paths:                      []string{"testfile"},
					APIKey:                     "test-key",
					ModelNames:                 []string{"test-model"},
					MaxConcurrentRequests:      0, // Minimum value
					RateLimitRequestsPerMinute: 1, // Minimum practical value
				}
			},
			expectError: false,
			description: "Boundary rate limiting values should be valid",
		},
		{
			name: "Very short timeout",
			setupFunc: func() *CliConfig {
				return &CliConfig{
					InstructionsFile: "instructions.md",
					Paths:            []string{"testfile"},
					APIKey:           "test-key",
					ModelNames:       []string{"test-model"},
					Timeout:          1 * time.Nanosecond, // Extremely short
				}
			},
			expectError: false,
			description: "Very short timeout values should be valid (though impractical)",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := tt.setupFunc()
			logger := &MockLogger{}

			err := ValidateConfig(config, logger)

			// Check if error matches expectation
			if (err != nil) != tt.expectError {
				t.Errorf("ValidateConfig() error = %v, expectError %v\nDescription: %s", err, tt.expectError, tt.description)
			}

			if tt.expectError && !logger.ErrorCalled {
				t.Errorf("Expected error to be logged, but no error was logged\nDescription: %s", tt.description)
			}

			if !tt.expectError && logger.ErrorCalled {
				t.Errorf("No error expected, but error was logged: %v\nDescription: %s", logger.ErrorMessages, tt.description)
			}
		})
	}
}

// Helper function for case-insensitive string matching
func containsIgnoreCase(s, substr string) bool {
	return len(substr) == 0 || indexIgnoreCase(s, substr) >= 0
}

func indexIgnoreCase(s, substr string) int {
	s, substr = strings.ToLower(s), strings.ToLower(substr)
	return strings.Index(s, substr)
}
