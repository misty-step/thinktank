// Package main provides the command-line interface for the thinktank tool
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

// TestCLIValidatesAllSupportedModels verifies that the CLI accepts all supported models
func TestCLIValidatesAllSupportedModels(t *testing.T) {
	// Removed t.Parallel() - uses filesystem operations and env variables
	// Create a temporary instructions file

	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Get all supported models
	supportedModels := models.ListAllModels()
	if len(supportedModels) != 39 {
		t.Fatalf("Expected 39 supported models (35 production + 4 test), got %d", len(supportedModels))
	}

	// Create a mock logger
	logger := logutil.NewTestLogger(t)

	// Test each model individually
	for _, modelName := range supportedModels {
		t.Run("Model_"+modelName, func(t *testing.T) {
			// Get the provider for this model to set the right API key
			provider, err := models.GetProviderForModel(modelName)
			if err != nil {
				t.Fatalf("Failed to get provider for model %s: %v", modelName, err)
			}

			// Create config with this model
			cfg := &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"testfile.go"},
				ModelNames:       []string{modelName},
			}

			// Mock environment function that returns appropriate API keys
			mockGetenv := func(key string) string {
				switch key {
				case "GEMINI_API_KEY":
					if provider == "gemini" {
						return "test-gemini-key"
					}
					return ""
				case "OPENAI_API_KEY":
					if provider == "openai" {
						return "test-openai-key"
					}
					return ""
				case "OPENROUTER_API_KEY":
					if provider == "openrouter" {
						return "test-openrouter-key"
					}
					return ""
				default:
					return ""
				}
			}

			// Validate the configuration
			err = ValidateInputsWithEnv(cfg, logger, mockGetenv)
			if err != nil {
				t.Errorf("Model %s (provider: %s) failed validation: %v", modelName, provider, err)
			}
		})
	}
}

// TestCLIValidatesMultipleModels verifies that the CLI accepts multiple models in one command
func TestCLIValidatesMultipleModels(t *testing.T) {
	// Removed t.Parallel() - uses filesystem operations and env variables
	// Create a temporary instructions file

	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Get OpenRouter production models (all production models now use OpenRouter)
	var openRouterModels []string
	for _, model := range models.ListAllModels() {
		provider, _ := models.GetProviderForModel(model)
		if provider == "openrouter" {
			openRouterModels = append(openRouterModels, model)
		}
	}

	// Test combinations of models
	testCases := []struct {
		name       string
		modelNames []string
		desc       string
	}{
		{
			name:       "Multiple OpenRouter models",
			modelNames: []string{"gpt-5.2", "gpt-5.2", "gemini-3-flash"},
			desc:       "multiple models from OpenRouter",
		},
		{
			name:       "OpenAI family via OpenRouter",
			modelNames: []string{"gpt-5.2", "gpt-5.2", "gpt-5.2"},
			desc:       "OpenAI models via OpenRouter",
		},
		{
			name:       "Gemini family via OpenRouter",
			modelNames: []string{"gemini-3-flash", "gemini-3-flash"},
			desc:       "Gemini models via OpenRouter",
		},
		{
			name:       "All production models",
			modelNames: openRouterModels,
			desc:       "all OpenRouter production models",
		},
		{
			name:       "All models including test",
			modelNames: models.ListAllModels(),
			desc:       "all supported models",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Create config with multiple models
			cfg := &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"testfile.go"},
				ModelNames:       tc.modelNames,
			}

			// Mock environment with OpenRouter API key (only key needed for production models)
			mockGetenv := func(key string) string {
				switch key {
				case "OPENROUTER_API_KEY":
					return "test-openrouter-key"
				default:
					return ""
				}
			}

			// Create logger
			logger := logutil.NewTestLogger(t)

			// Validate the configuration
			err := ValidateInputsWithEnv(cfg, logger, mockGetenv)
			if err != nil {
				t.Errorf("Failed to validate %s: %v", tc.desc, err)
			}
		})
	}
}

// TestCLISynthesisModelValidation verifies synthesis model validation works for all models
func TestCLISynthesisModelValidation(t *testing.T) {
	// Removed t.Parallel() - uses filesystem operations and env variables
	// Create a temporary instructions file

	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Get all supported models
	supportedModels := models.ListAllModels()

	// Test each model as a synthesis model
	for _, synthesisModel := range supportedModels {
		t.Run("Synthesis_"+synthesisModel, func(t *testing.T) {
			// Create config with synthesis model
			cfg := &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"testfile.go"},
				ModelNames:       []string{supportedModels[0]}, // Use first model as primary
				SynthesisModel:   synthesisModel,
			}

			// Mock environment with all API keys
			mockGetenv := func(key string) string {
				switch key {
				case "GEMINI_API_KEY":
					return "test-gemini-key"
				case "OPENAI_API_KEY":
					return "test-openai-key"
				case "OPENROUTER_API_KEY":
					return "test-openrouter-key"
				default:
					return ""
				}
			}

			// Create logger
			logger := logutil.NewTestLogger(t)

			// Validate the configuration
			err := ValidateInputsWithEnv(cfg, logger, mockGetenv)
			if err != nil {
				t.Errorf("Model %s failed synthesis model validation: %v", synthesisModel, err)
			}
		})
	}
}

// TestCLIRejectsInvalidModels verifies that the CLI rejects invalid model names with appropriate errors
func TestCLIRejectsInvalidModels(t *testing.T) {
	// Removed t.Parallel() - uses filesystem operations and env variables
	// Create a temporary instructions file

	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Test cases with invalid model names
	testCases := []struct {
		name          string
		modelNames    []string
		errorContains string
	}{
		{
			name:          "Completely invalid model",
			modelNames:    []string{"invalid-model-name"},
			errorContains: "unknown model",
		},
		{
			name:          "GPT model that doesn't exist",
			modelNames:    []string{"gpt-6"},
			errorContains: "unknown model",
		},
		{
			name:          "Gemini model that doesn't exist",
			modelNames:    []string{"gemini-ultra"},
			errorContains: "unknown model",
		},
		{
			name:          "Misspelled model name",
			modelNames:    []string{"gpt4.1"}, // Missing hyphen
			errorContains: "unknown model",
		},
		{
			name:          "Mixed valid and invalid",
			modelNames:    []string{"gpt-5.2", "invalid-model"},
			errorContains: "unknown model",
		},
		{
			name:          "Empty model name",
			modelNames:    []string{""},
			errorContains: "unknown model",
		},
		{
			name:          "Model with wrong provider prefix",
			modelNames:    []string{"anthropic/claude-3"},
			errorContains: "unknown model",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Create config with invalid models
			cfg := &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"testfile.go"},
				ModelNames:       tc.modelNames,
			}

			// Mock environment with all API keys
			mockGetenv := func(key string) string {
				switch key {
				case "GEMINI_API_KEY":
					return "test-gemini-key"
				case "OPENAI_API_KEY":
					return "test-openai-key"
				case "OPENROUTER_API_KEY":
					return "test-openrouter-key"
				default:
					return ""
				}
			}

			// Create logger - use buffer logger to avoid test failure on expected errors
			logger := logutil.NewBufferLogger(logutil.DebugLevel)

			// Validate the configuration - should fail
			err := ValidateInputsWithEnv(cfg, logger, mockGetenv)
			if err == nil {
				t.Error("Expected validation to fail for invalid model, but it succeeded")
			} else if !strings.Contains(err.Error(), tc.errorContains) {
				t.Errorf("Expected error to contain '%s', got: %v", tc.errorContains, err)
			}
		})
	}
}

// TestCLIRejectsInvalidSynthesisModels verifies synthesis model validation rejects invalid models
func TestCLIRejectsInvalidSynthesisModels(t *testing.T) {
	// Removed t.Parallel() - uses filesystem operations and env variables
	// Create a temporary instructions file

	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Get a valid model for primary
	supportedModels := models.ListAllModels()

	// Test cases with invalid synthesis models
	testCases := []struct {
		name           string
		synthesisModel string
		errorContains  string
	}{
		{
			name:           "Invalid synthesis model",
			synthesisModel: "invalid-synthesis-model",
			errorContains:  "invalid synthesis model",
		},
		{
			name:           "Non-existent GPT model",
			synthesisModel: "gpt-6-turbo",
			errorContains:  "invalid synthesis model",
		},
		{
			name:           "Misspelled synthesis model",
			synthesisModel: "gemini2.5pro",
			errorContains:  "invalid synthesis model",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Create config with invalid synthesis model
			cfg := &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"testfile.go"},
				ModelNames:       []string{supportedModels[0]},
				SynthesisModel:   tc.synthesisModel,
			}

			// Mock environment with all API keys
			mockGetenv := func(key string) string {
				switch key {
				case "GEMINI_API_KEY":
					return "test-gemini-key"
				case "OPENAI_API_KEY":
					return "test-openai-key"
				case "OPENROUTER_API_KEY":
					return "test-openrouter-key"
				default:
					return ""
				}
			}

			// Create logger - use buffer logger to avoid test failure on expected errors
			logger := logutil.NewBufferLogger(logutil.DebugLevel)

			// Validate the configuration - should fail
			err := ValidateInputsWithEnv(cfg, logger, mockGetenv)
			if err == nil {
				t.Error("Expected validation to fail for invalid synthesis model, but it succeeded")
			} else if !strings.Contains(err.Error(), tc.errorContains) {
				t.Errorf("Expected error to contain '%s', got: %v", tc.errorContains, err)
			}
		})
	}
}

// TestCLIAPIKeyValidation verifies that the CLI checks the correct environment variables for each provider
func TestCLIAPIKeyValidation(t *testing.T) {
	// Removed t.Parallel() - uses filesystem operations and env variables
	// Create a temporary instructions file

	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Group models by provider
	modelsByProvider := make(map[string][]string)
	for _, model := range models.ListAllModels() {
		provider, _ := models.GetProviderForModel(model)
		modelsByProvider[provider] = append(modelsByProvider[provider], model)
	}

	// Test each provider's models
	for provider, providerModels := range modelsByProvider {
		t.Run("Provider_"+provider, func(t *testing.T) {
			// Determine the expected environment variable and error message
			var expectedEnvVar, expectedError string
			switch provider {
			case "gemini":
				expectedEnvVar = "GEMINI_API_KEY"
				expectedError = "gemini API key not set"
			case "openai":
				expectedEnvVar = "OPENAI_API_KEY"
				expectedError = "openAI API key not set"
			case "openrouter":
				expectedEnvVar = "OPENROUTER_API_KEY"
				expectedError = "OpenRouter API key not set - get your key at https://openrouter.ai/keys"
			case "test":
				// Test provider doesn't require API keys
				expectedEnvVar = ""
				expectedError = ""
			}

			// Test with missing API key
			t.Run("Missing_API_Key", func(t *testing.T) {
				for _, model := range providerModels {
					t.Run("Model_"+model, func(t *testing.T) {
						cfg := &config.CliConfig{
							InstructionsFile: instructionsFile,
							Paths:            []string{"testfile.go"},
							ModelNames:       []string{model},
						}

						// Mock environment with no API keys
						mockGetenv := func(key string) string {
							return "" // All API keys missing
						}

						// Create logger
						logger := logutil.NewBufferLogger(logutil.DebugLevel)

						// Validate - should fail with missing API key error (except for test provider)
						err := ValidateInputsWithEnv(cfg, logger, mockGetenv)
						if provider == "test" {
							// Test provider should succeed without API keys
							if err != nil {
								t.Errorf("Test provider should not require API key, but got error: %v", err)
							}
						} else {
							// Production providers should fail without API keys
							if err == nil {
								t.Error("Expected validation to fail due to missing API key")
							} else if !strings.Contains(err.Error(), expectedError) {
								t.Errorf("Expected error '%s', got: %v", expectedError, err)
							}
						}
					})
				}
			})

			// Test with correct API key
			t.Run("With_Correct_API_Key", func(t *testing.T) {
				for _, model := range providerModels {
					t.Run("Model_"+model, func(t *testing.T) {
						cfg := &config.CliConfig{
							InstructionsFile: instructionsFile,
							Paths:            []string{"testfile.go"},
							ModelNames:       []string{model},
						}

						// Mock environment with correct API key
						mockGetenv := func(key string) string {
							if key == expectedEnvVar {
								return "test-api-key-value"
							}
							return ""
						}

						// Create logger
						logger := logutil.NewBufferLogger(logutil.DebugLevel)

						// Validate - should succeed
						err := ValidateInputsWithEnv(cfg, logger, mockGetenv)
						if err != nil {
							t.Errorf("Validation failed with correct API key: %v", err)
						}
					})
				}
			})

			// Test with wrong API key (different provider's key)
			t.Run("With_Wrong_Provider_Key", func(t *testing.T) {
				// Skip if there's only one provider
				if len(modelsByProvider) <= 1 {
					t.Skip("Only one provider available, cannot test wrong provider key")
				}

				// Get a different provider's env var
				var wrongEnvVar string
				for otherProvider := range modelsByProvider {
					if otherProvider != provider {
						wrongEnvVar = models.GetAPIKeyEnvVar(otherProvider)
						break
					}
				}

				for _, model := range providerModels {
					t.Run("Model_"+model, func(t *testing.T) {
						cfg := &config.CliConfig{
							InstructionsFile: instructionsFile,
							Paths:            []string{"testfile.go"},
							ModelNames:       []string{model},
						}

						// Mock environment with wrong provider's API key
						mockGetenv := func(key string) string {
							if key == wrongEnvVar {
								return "wrong-provider-api-key"
							}
							return ""
						}

						// Create logger
						logger := logutil.NewBufferLogger(logutil.DebugLevel)

						// Validate - should fail (except for test provider)
						err := ValidateInputsWithEnv(cfg, logger, mockGetenv)
						if provider == "test" {
							// Test provider should succeed regardless of API keys
							if err != nil {
								t.Errorf("Test provider should not require API key, but got error: %v", err)
							}
						} else {
							// Production providers should fail with wrong API keys
							if err == nil {
								t.Error("Expected validation to fail with wrong provider API key")
							} else if !strings.Contains(err.Error(), expectedError) {
								t.Errorf("Expected error '%s', got: %v", expectedError, err)
							}
						}
					})
				}
			})
		})
	}
}

// TestCLIMultiProviderAPIKeyValidation tests API key validation for OpenRouter models
func TestCLIMultiProviderAPIKeyValidation(t *testing.T) {
	// Removed t.Parallel() - uses filesystem operations and env variables
	// Create a temporary instructions file

	tempDir := t.TempDir()
	instructionsFile := filepath.Join(tempDir, "instructions.txt")
	if err := os.WriteFile(instructionsFile, []byte("test instructions"), 0644); err != nil {
		t.Fatalf("Failed to create test instructions file: %v", err)
	}

	// Get some OpenRouter models for testing
	var openRouterModels []string
	for _, model := range models.ListAllModels() {
		provider, _ := models.GetProviderForModel(model)
		if provider == "openrouter" {
			openRouterModels = append(openRouterModels, model)
			if len(openRouterModels) >= 3 {
				break // We only need a few models for testing
			}
		}
	}

	testCases := []struct {
		name          string
		models        []string
		missingKeys   []string
		expectError   bool
		errorContains string
	}{
		{
			name:          "OpenRouter API key present",
			models:        openRouterModels,
			missingKeys:   []string{},
			expectError:   false,
			errorContains: "",
		},
		{
			name:          "Missing OpenRouter API key",
			models:        []string{"gpt-5.2", "gemini-3-flash"},
			missingKeys:   []string{"OPENROUTER_API_KEY"},
			expectError:   true,
			errorContains: "OpenRouter API key not set - get your key at https://openrouter.ai/keys",
		},
		{
			name:          "Old API keys present but not needed",
			models:        []string{"gpt-5.2", "gpt-5.2"},
			missingKeys:   []string{"OPENROUTER_API_KEY"},
			expectError:   true,
			errorContains: "OpenRouter API key not set - get your key at https://openrouter.ai/keys",
		},
		{
			name:          "Single model without API key",
			models:        []string{"gemini-3-flash"},
			missingKeys:   []string{"OPENROUTER_API_KEY"},
			expectError:   true,
			errorContains: "OpenRouter API key not set - get your key at https://openrouter.ai/keys",
		},
		{
			name:          "All models with API key",
			models:        models.ListAllModels(),
			missingKeys:   []string{},
			expectError:   false,
			errorContains: "",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			cfg := &config.CliConfig{
				InstructionsFile: instructionsFile,
				Paths:            []string{"testfile.go"},
				ModelNames:       tc.models,
			}

			// Mock environment
			mockGetenv := func(key string) string {
				// Check if this key should be missing
				for _, missingKey := range tc.missingKeys {
					if key == missingKey {
						return ""
					}
				}
				// Otherwise return a test value
				return "test-api-key"
			}

			// Create logger
			logger := logutil.NewBufferLogger(logutil.DebugLevel)

			// Validate
			err := ValidateInputsWithEnv(cfg, logger, mockGetenv)

			if tc.expectError {
				if err == nil {
					t.Error("Expected validation to fail but it succeeded")
				} else if !strings.Contains(err.Error(), tc.errorContains) {
					t.Errorf("Expected error to contain '%s', got: %v", tc.errorContains, err)
				}
			} else {
				if err != nil {
					t.Errorf("Expected validation to succeed but got error: %v", err)
				}
			}
		})
	}
}

// TestCLIAPIKeyEnvironmentVariableNames verifies the correct environment variable names for each provider
func TestCLIAPIKeyEnvironmentVariableNames(t *testing.T) {
	// Removed t.Parallel() - uses environment variables
	testCases := []struct {
		provider string
		expected string
	}{
		{provider: "openrouter", expected: "OPENROUTER_API_KEY"},
		{provider: "test", expected: ""}, // Test provider doesn't require API key
	}

	for _, tc := range testCases {
		t.Run("Provider_"+tc.provider, func(t *testing.T) {
			actual := models.GetAPIKeyEnvVar(tc.provider)
			if actual != tc.expected {
				t.Errorf("Expected environment variable '%s' for provider '%s', got '%s'",
					tc.expected, tc.provider, actual)
			}
		})
	}

	// Test obsolete providers return empty string
	t.Run("Obsolete_Providers", func(t *testing.T) {
		obsoleteProviders := []string{"openai", "gemini", "anthropic"}
		for _, provider := range obsoleteProviders {
			result := models.GetAPIKeyEnvVar(provider)
			if result != "" {
				t.Errorf("Expected empty string for obsolete provider '%s', got '%s'", provider, result)
			}
		}
	})

	// Test unknown provider
	t.Run("Unknown_Provider", func(t *testing.T) {
		result := models.GetAPIKeyEnvVar("unknown-provider")
		if result != "" {
			t.Errorf("Expected empty string for unknown provider, got '%s'", result)
		}
	})
}
