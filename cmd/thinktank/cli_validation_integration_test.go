// Package main provides integration tests for CLI validation functionality
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/misty-step/thinktank/internal/config"
	"github.com/misty-step/thinktank/internal/logutil"
	"github.com/misty-step/thinktank/internal/models"
)

// TestValidateInputsIntegration tests the main ValidateInputs function with real environment variables
func TestValidateInputsIntegration(t *testing.T) {
	// Removed t.Parallel() - modifies environment variables
	// Save original environment variables

	originalGeminiKey := os.Getenv("GEMINI_API_KEY")
	originalOpenAIKey := os.Getenv("OPENAI_API_KEY")
	originalOpenRouterKey := os.Getenv("OPENROUTER_API_KEY")

	defer func() {
		// Restore original environment
		if originalGeminiKey != "" {
			if err := os.Setenv("GEMINI_API_KEY", originalGeminiKey); err != nil {
				t.Errorf("Failed to restore GEMINI_API_KEY: %v", err)
			}
		} else {
			if err := os.Unsetenv("GEMINI_API_KEY"); err != nil {
				t.Errorf("Failed to unset GEMINI_API_KEY: %v", err)
			}
		}
		if originalOpenAIKey != "" {
			if err := os.Setenv("OPENAI_API_KEY", originalOpenAIKey); err != nil {
				t.Errorf("Failed to restore OPENAI_API_KEY: %v", err)
			}
		} else {
			if err := os.Unsetenv("OPENAI_API_KEY"); err != nil {
				t.Errorf("Failed to unset OPENAI_API_KEY: %v", err)
			}
		}
		if originalOpenRouterKey != "" {
			if err := os.Setenv("OPENROUTER_API_KEY", originalOpenRouterKey); err != nil {
				t.Errorf("Failed to restore OPENROUTER_API_KEY: %v", err)
			}
		} else {
			if err := os.Unsetenv("OPENROUTER_API_KEY"); err != nil {
				t.Errorf("Failed to unset OPENROUTER_API_KEY: %v", err)
			}
		}
	}()

	// Create a temporary instructions file
	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Use buffer logger instead of test logger to avoid failing on expected error logs
	logger := logutil.NewBufferLogger(logutil.InfoLevel)

	// Use specific model names directly - all production models now use OpenRouter
	// After OpenRouter consolidation, all models use "openrouter" provider
	geminiModel := "gemini-3-flash"    // Former Gemini model, now uses OpenRouter
	openAIModel := "gpt-5.2"           // Former OpenAI model, now uses OpenRouter
	openRouterModel := "deepseek-v3.2" // Explicit OpenRouter model

	// Verify these models actually exist
	supportedModels := models.ListAllModels()
	modelExists := func(modelName string) bool {
		for _, model := range supportedModels {
			if model == modelName {
				return true
			}
		}
		return false
	}

	if !modelExists(geminiModel) {
		t.Fatalf("Test model %s not found in supported models", geminiModel)
	}
	if !modelExists(openAIModel) {
		t.Fatalf("Test model %s not found in supported models", openAIModel)
	}
	if !modelExists(openRouterModel) {
		t.Fatalf("Test model %s not found in supported models", openRouterModel)
	}

	tests := []struct {
		name          string
		config        *config.CliConfig
		envVars       map[string]string
		expectError   bool
		errorContains string
	}{
		{
			name: "Valid configuration with Gemini model",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"src/"},
				ModelNames:       []string{geminiModel},
			},
			envVars: map[string]string{
				"OPENROUTER_API_KEY": "test-openrouter-api-key",
			},
			expectError: false,
		},
		{
			name: "Valid configuration with OpenAI model",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"src/"},
				ModelNames:       []string{openAIModel},
			},
			envVars: map[string]string{
				"OPENROUTER_API_KEY": "test-openrouter-api-key",
			},
			expectError: false,
		},
		{
			name: "Valid configuration with OpenRouter model",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"src/"},
				ModelNames:       []string{openRouterModel},
			},
			envVars: map[string]string{
				"OPENROUTER_API_KEY": "test-openrouter-api-key",
			},
			expectError: false,
		},
		{
			name: "Missing API key for Gemini model",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"src/"},
				ModelNames:       []string{geminiModel},
			},
			envVars:       map[string]string{}, // No API key set
			expectError:   true,
			errorContains: "OpenRouter API key not set",
		},
		{
			name: "Missing API key for OpenAI model",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"src/"},
				ModelNames:       []string{openAIModel},
			},
			envVars:       map[string]string{}, // No API key set
			expectError:   true,
			errorContains: "OpenRouter API key not set",
		},
		{
			name: "Missing OpenRouter API key",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"src/"},
				ModelNames:       []string{openRouterModel},
			},
			envVars:       map[string]string{}, // No API key set
			expectError:   true,
			errorContains: "OpenRouter API key not set",
		},
		{
			name: "Multiple models with unified OpenRouter provider",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"src/"},
				ModelNames:       []string{openAIModel, geminiModel},
			},
			envVars: map[string]string{
				"OPENROUTER_API_KEY": "test-openrouter-api-key",
			},
			expectError: false,
		},
		{
			name: "Dry run mode bypasses API key requirements",
			config: &config.CliConfig{
				InstructionsFile: "", // Not required for dry run
				Paths:            []string{"src/"},
				ModelNames:       []string{}, // Not required for dry run
				DryRun:           true,
			},
			envVars:     map[string]string{}, // No API keys needed
			expectError: false,
		},
		{
			name: "Missing instructions file (non-dry-run)",
			config: &config.CliConfig{
				InstructionsFile: "",
				Paths:            []string{"src/"},
				ModelNames:       []string{geminiModel},
				DryRun:           false,
			},
			envVars:       map[string]string{}, // validation fails before API key check
			expectError:   true,
			errorContains: "missing required --instructions flag",
		},
		{
			name: "Missing paths",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{}, // No paths provided
				ModelNames:       []string{geminiModel},
				DryRun:           false,
			},
			envVars:       map[string]string{}, // validation fails before API key check
			expectError:   true,
			errorContains: "no paths specified",
		},
		{
			name: "Missing models (non-dry-run)",
			config: &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"src/"},
				ModelNames:       []string{}, // No models specified
				DryRun:           false,
			},
			envVars:       map[string]string{}, // validation fails before API key check
			expectError:   true,
			errorContains: "no models specified",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clear all environment variables first
			for _, key := range []string{"GEMINI_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY"} {
				if err := os.Unsetenv(key); err != nil {
					t.Fatalf("Failed to unset %s: %v", key, err)
				}
			}

			// Set test environment variables
			for key, value := range tt.envVars {
				if err := os.Setenv(key, value); err != nil {
					t.Fatalf("Failed to set %s: %v", key, err)
				}
			}

			// Call the actual ValidateInputs function
			err := ValidateInputs(tt.config, logger)

			// Check error expectation
			if tt.expectError {
				if err == nil {
					t.Errorf("Expected error but got none")
					return
				}
				if tt.errorContains != "" && !strings.Contains(err.Error(), tt.errorContains) {
					t.Errorf("Expected error to contain %q, got %q", tt.errorContains, err.Error())
				}
				return
			}

			// Check for unexpected error
			if err != nil {
				t.Errorf("Unexpected error: %v", err)
			}
		})
	}
}

// TestValidateInputsEdgeCases tests additional edge cases to improve ValidateInputsWithEnv coverage
func TestValidateInputsEdgeCases(t *testing.T) {
	// Removed t.Parallel() - uses environment variables
	// Create a temporary instructions file

	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Use buffer logger instead of test logger to avoid failing on expected error logs
	logger := logutil.NewBufferLogger(logutil.InfoLevel)

	t.Run("Synthesis model with invalid model", func(t *testing.T) {
		config := &config.CliConfig{
			InstructionsFile: instructionsFile,
			Paths:            []string{"src/"},
			ModelNames:       []string{"gemini-3-flash"},
			SynthesisModel:   "totally-invalid-model-name",
		}

		getenv := func(key string) string {
			if key == "OPENROUTER_API_KEY" {
				return "test-openrouter-key"
			}
			return ""
		}

		err := ValidateInputsWithEnv(config, logger, getenv)
		if err == nil {
			t.Error("Expected error for invalid synthesis model")
		}
		if !strings.Contains(err.Error(), "invalid synthesis model") {
			t.Errorf("Expected error to contain synthesis model validation message, got: %v", err)
		}
	})

	t.Run("Synthesis model with valid supported model", func(t *testing.T) {
		config := &config.CliConfig{
			InstructionsFile: instructionsFile,
			Paths:            []string{"src/"},
			ModelNames:       []string{"gemini-3-flash"},
			SynthesisModel:   "gpt-5.2", // Valid supported model
		}

		getenv := func(key string) string {
			if key == "OPENROUTER_API_KEY" {
				return "test-openrouter-key"
			}
			return ""
		}

		err := ValidateInputsWithEnv(config, logger, getenv)
		if err != nil {
			t.Errorf("Unexpected error for valid synthesis model: %v", err)
		}
	})
}
