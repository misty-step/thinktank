package thinktank

import (
	"context"
	"os"
	"testing"

	"github.com/misty-step/thinktank/internal/models"
	"github.com/misty-step/thinktank/internal/testutil"
)

// TestRegistryAPIWithModelsPackage verifies that RegistryAPIService works correctly
// with the new models package for all supported models
func TestRegistryAPIWithModelsPackage(t *testing.T) {
	// Save and restore environment
	originalAPIKeys := map[string]string{
		"OPENAI_API_KEY":     os.Getenv("OPENAI_API_KEY"),
		"GEMINI_API_KEY":     os.Getenv("GEMINI_API_KEY"),
		"OPENROUTER_API_KEY": os.Getenv("OPENROUTER_API_KEY"),
	}

	defer func() {
		for key, value := range originalAPIKeys {
			if value == "" {
				if err := os.Unsetenv(key); err != nil {
					t.Errorf("Failed to unset %s: %v", key, err)
				}
			} else {
				if err := os.Setenv(key, value); err != nil {
					t.Errorf("Failed to restore %s: %v", key, err)
				}
			}
		}
	}()

	// Set realistic test API keys
	testKeys := map[string]string{
		"OPENAI_API_KEY":     "sk-test_openai_key_1234567890abcdefghijklmnopqrstuvwxyz",
		"GEMINI_API_KEY":     "test_gemini_key_1234567890abcdefghijklmnopqrstuvwxyz",
		"OPENROUTER_API_KEY": "sk-or-test_openrouter_key_1234567890abcdefghijklmnopqrstuvwxyz",
	}

	for key, value := range testKeys {
		if err := os.Setenv(key, value); err != nil {
			t.Fatalf("Failed to set %s: %v", key, err)
		}
	}

	logger := testutil.NewMockLogger()
	service := NewRegistryAPIService(logger)
	ctx := context.Background()

	// Test all models work with the service (35 production + 4 test)
	allModels := models.ListAllModels()
	if len(allModels) != 39 {
		t.Fatalf("Expected 39 models (35 production + 4 test), got %d", len(allModels))
	}

	for _, modelName := range allModels {
		t.Run(modelName, func(t *testing.T) {
			// Skip test models - they don't work with real API services
			provider, err := models.GetProviderForModel(modelName)
			if err != nil {
				t.Errorf("Failed to get provider for %s: %v", modelName, err)
				return
			}
			if provider == "test" {
				t.Skipf("Skipping test model %s - not for use with real API services", modelName)
			}

			// Test InitLLMClient
			client, err := service.InitLLMClient(ctx, "", modelName, "")
			if err != nil {
				t.Errorf("InitLLMClient failed for %s: %v", modelName, err)
				return
			}
			if client == nil {
				t.Errorf("InitLLMClient returned nil client for %s", modelName)
				return
			}

			// Test GetModelParameters
			params, err := service.GetModelParameters(ctx, modelName)
			if err != nil {
				t.Errorf("GetModelParameters failed for %s: %v", modelName, err)
				return
			}
			if len(params) == 0 {
				t.Errorf("GetModelParameters returned empty params for %s", modelName)
			}

			// Test GetModelTokenLimits
			contextWindow, maxOutput, err := service.GetModelTokenLimits(ctx, modelName)
			if err != nil {
				t.Errorf("GetModelTokenLimits failed for %s: %v", modelName, err)
				return
			}
			if contextWindow <= 0 || maxOutput <= 0 {
				t.Errorf("Invalid token limits for %s: context=%d, output=%d",
					modelName, contextWindow, maxOutput)
			}

			// Test ValidateModelParameter with temperature
			valid, err := service.ValidateModelParameter(ctx, modelName, "temperature", 0.7)
			if err != nil {
				t.Errorf("ValidateModelParameter failed for %s: %v", modelName, err)
				return
			}
			if !valid {
				t.Errorf("ValidateModelParameter rejected valid temperature for %s", modelName)
			}
		})
	}
}

// TestRegistryAPIErrorHandling tests error scenarios
func TestRegistryAPIErrorHandling(t *testing.T) {
	logger := testutil.NewMockLogger()
	service := NewRegistryAPIService(logger)
	ctx := context.Background()

	// Test with invalid model
	_, err := service.InitLLMClient(ctx, "", "invalid-model", "")
	if err == nil {
		t.Error("Expected error for invalid model")
	}

	// Test parameter validation with invalid values
	valid, err := service.ValidateModelParameter(ctx, "gpt-5.2", "temperature", 5.0)
	if err == nil {
		t.Error("Expected error for invalid temperature value")
	}
	if valid {
		t.Error("Expected temperature 5.0 to be invalid")
	}
}

// TestProviderDistribution verifies correct provider mapping
func TestProviderDistribution(t *testing.T) {
	openaiModels := models.ListModelsForProvider("openai")
	geminiModels := models.ListModelsForProvider("gemini")
	openrouterModels := models.ListModelsForProvider("openrouter")
	testModels := models.ListModelsForProvider("test")

	if len(openaiModels) != 0 {
		t.Errorf("Expected 0 OpenAI models after consolidation, got %d", len(openaiModels))
	}
	if len(geminiModels) != 0 {
		t.Errorf("Expected 0 Gemini models after consolidation, got %d", len(geminiModels))
	}
	if len(openrouterModels) != 35 {
		t.Errorf("Expected 35 OpenRouter models after consolidation, got %d", len(openrouterModels))
	}
	if len(testModels) != 4 {
		t.Errorf("Expected 4 test models, got %d", len(testModels))
	}

	total := len(openaiModels) + len(geminiModels) + len(openrouterModels) + len(testModels)
	if total != 39 {
		t.Errorf("Expected total 39 models (35 production + 4 test), got %d", total)
	}
}
