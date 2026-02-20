// Package models provides model configuration and selection functionality
package models

import (
	"testing"
)

func TestGetModelsWithMinContextWindow(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name           string
		minTokens      int
		expectedModels []string
		verifyOrder    bool
	}{
		{
			name:      "very small threshold includes all models",
			minTokens: 1000,
			expectedModels: []string{
				// Test models
				"synthesis-model",
				"model1",
				"model2",
				"model3",
				// Production models (sorted by context window desc)
				"grok-4.1-fast",          // 2M
				"llama-4-maverick",       // 1M
				"gemini-3-flash",         // 1M
				"gemini-3-pro",           // 1M
				"gemini-3.1-pro",         // 1M
				"claude-sonnet-4.5",      // 1M
				"gpt-5.2",                // 400K
				"gpt-5.2-codex",          // 400K
				"openai/gpt-5.2-codex",   // 400K
				"moonshotai/kimi-k2.5",   // 262K
				"qwen/qwen3-coder",       // 262K
				"devstral-2",             // 262K
				"grok-code-fast-1",       // 256K
				"glm-4.7",                // 202K
				"claude-opus-4-6",        // 200K
				"claude-opus-4.5",        // 200K
				"claude-sonnet-4-6",      // 200K
				"minimax-m2.1",           // 196K
				"deepseek-v3.2",          // 163K
				"deepseek-v3.2-speciale", // 163K
			},
			verifyOrder: true,
		},
		{
			name:      "medium threshold filters some models",
			minTokens: 100000,
			expectedModels: []string{
				"grok-4.1-fast",
				"llama-4-maverick",
				"gemini-3-flash",
				"gemini-3-pro",
				"gemini-3.1-pro",
				"claude-sonnet-4.5",
				"gpt-5.2",
				"gpt-5.2-codex",
				"openai/gpt-5.2-codex",
				"moonshotai/kimi-k2.5",
				"qwen/qwen3-coder",
				"devstral-2",
				"grok-code-fast-1",
				"glm-4.7",
				"claude-opus-4-6",
				"claude-opus-4.5",
				"claude-sonnet-4-6",
				"minimax-m2.1",
				"deepseek-v3.2",
				"deepseek-v3.2-speciale",
			},
			verifyOrder: true,
		},
		{
			name:      "high threshold only largest models",
			minTokens: 500000,
			expectedModels: []string{
				"grok-4.1-fast",
				"llama-4-maverick",
				"gemini-3-flash",
				"gemini-3-pro",
				"gemini-3.1-pro",
				"claude-sonnet-4.5",
			},
			verifyOrder: true,
		},
		{
			name:      "very high threshold",
			minTokens: 900000,
			expectedModels: []string{
				"grok-4.1-fast",
				"llama-4-maverick",
				"gemini-3-flash",
				"gemini-3-pro",
				"gemini-3.1-pro",
				"claude-sonnet-4.5",
			},
			verifyOrder: true,
		},
		{
			name:      "threshold above most models (1M context)",
			minTokens: 1000000,
			expectedModels: []string{
				"grok-4.1-fast",
				"llama-4-maverick",
				"gemini-3-flash",
				"gemini-3-pro",
				"gemini-3.1-pro",
				"claude-sonnet-4.5",
			},
			verifyOrder: true,
		},
		{
			name:      "only 2M context models",
			minTokens: 1500000,
			expectedModels: []string{
				"grok-4.1-fast",
			},
			verifyOrder: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GetModelsWithMinContextWindow(tt.minTokens)

			// Verify correct number of models
			if len(result) != len(tt.expectedModels) {
				t.Errorf("GetModelsWithMinContextWindow(%d) returned %d models, want %d\nGot: %v\nWant: %v",
					tt.minTokens, len(result), len(tt.expectedModels), result, tt.expectedModels)
			}

			// Create set of expected models for easy lookup
			expectedSet := make(map[string]bool)
			for _, model := range tt.expectedModels {
				expectedSet[model] = true
			}

			// Verify all returned models are expected
			for _, modelName := range result {
				if !expectedSet[modelName] {
					t.Errorf("GetModelsWithMinContextWindow(%d) returned unexpected model: %s",
						tt.minTokens, modelName)
				}
			}

			// Verify all expected models are present
			resultSet := make(map[string]bool)
			for _, model := range result {
				resultSet[model] = true
			}
			for _, expected := range tt.expectedModels {
				if !resultSet[expected] {
					t.Errorf("GetModelsWithMinContextWindow(%d) missing expected model: %s",
						tt.minTokens, expected)
				}
			}

			// Verify descending order by context window (largest first)
			if tt.verifyOrder && len(result) > 1 {
				for i := 0; i < len(result)-1; i++ {
					info1, err1 := GetModelInfo(result[i])
					info2, err2 := GetModelInfo(result[i+1])
					if err1 != nil || err2 != nil {
						t.Errorf("GetModelsWithMinContextWindow(%d) returned invalid model names: %v, %v",
							tt.minTokens, err1, err2)
						continue
					}
					if info1.ContextWindow < info2.ContextWindow {
						t.Errorf("GetModelsWithMinContextWindow(%d) not properly sorted: "+
							"models[%d]=%s (%d tokens) < models[%d]=%s (%d tokens)",
							tt.minTokens, i, result[i], info1.ContextWindow, i+1, result[i+1], info2.ContextWindow)
					}
				}
			}

			// Verify all returned models meet the minimum threshold
			for _, modelName := range result {
				info, err := GetModelInfo(modelName)
				if err != nil {
					t.Errorf("GetModelsWithMinContextWindow(%d) returned invalid model: %s",
						tt.minTokens, modelName)
					continue
				}
				if info.ContextWindow < tt.minTokens {
					t.Errorf("GetModelsWithMinContextWindow(%d) returned model %s with context window %d < %d",
						tt.minTokens, modelName, info.ContextWindow, tt.minTokens)
				}
			}
		})
	}
}

func TestSelectModelsForInput(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name               string
		estimatedTokens    int
		availableProviders []string
		expectedModels     []string
		verifyOrder        bool
	}{
		{
			name:               "small input, openrouter provider",
			estimatedTokens:    5000,
			availableProviders: []string{"openrouter"},
			expectedModels: []string{
				"grok-4.1-fast",
				"llama-4-maverick",
				"gemini-3-flash",
				"gemini-3-pro",
				"gemini-3.1-pro",
				"claude-sonnet-4.5",
				"gpt-5.2",
				"gpt-5.2-codex",
				"openai/gpt-5.2-codex",
				"moonshotai/kimi-k2.5",
				"qwen/qwen3-coder",
				"devstral-2",
				"grok-code-fast-1",
				"glm-4.7",
				"deepseek-v3.2",
				"claude-opus-4-6",
				"claude-opus-4.5",
				"claude-sonnet-4-6",
				"minimax-m2.1",
				"deepseek-v3.2-speciale",
			},
			verifyOrder: true,
		},
		{
			name:               "obsolete gemini provider (no models)",
			estimatedTokens:    50000,
			availableProviders: []string{"gemini"},
			expectedModels:     []string{},
			verifyOrder:        false,
		},
		{
			name:               "very large input, limited models",
			estimatedTokens:    700000,
			availableProviders: []string{"openrouter"},
			expectedModels: []string{
				"grok-4.1-fast",
				"llama-4-maverick",
				"gemini-3-flash",
				"gemini-3-pro",
				"gemini-3.1-pro",
				"claude-sonnet-4.5",
			},
			verifyOrder: true,
		},
		{
			name:               "obsolete openai provider (no models)",
			estimatedTokens:    10000,
			availableProviders: []string{"openai"},
			expectedModels:     []string{},
			verifyOrder:        false,
		},
		{
			name:               "empty providers",
			estimatedTokens:    10000,
			availableProviders: []string{},
			expectedModels:     []string{},
			verifyOrder:        false,
		},
		{
			name:               "unknown provider",
			estimatedTokens:    10000,
			availableProviders: []string{"unknown-provider"},
			expectedModels:     []string{},
			verifyOrder:        false,
		},
		{
			name:               "extremely large input, only 2M context models",
			estimatedTokens:    1200000,
			availableProviders: []string{"openrouter"},
			expectedModels: []string{
				"grok-4.1-fast", // Only 2M context model qualifies
			},
			verifyOrder: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := SelectModelsForInput(tt.estimatedTokens, tt.availableProviders)

			// Verify correct number of models
			if len(result) != len(tt.expectedModels) {
				t.Errorf("SelectModelsForInput(%d, %v) returned %d models, want %d\nGot: %v\nWant: %v",
					tt.estimatedTokens, tt.availableProviders, len(result), len(tt.expectedModels), result, tt.expectedModels)
			}

			// Create set of expected models for easy lookup
			expectedSet := make(map[string]bool)
			for _, model := range tt.expectedModels {
				expectedSet[model] = true
			}

			// Verify all returned models are expected
			for _, modelName := range result {
				if !expectedSet[modelName] {
					t.Errorf("SelectModelsForInput(%d, %v) returned unexpected model: %s",
						tt.estimatedTokens, tt.availableProviders, modelName)
				}
			}

			// Verify all expected models are present
			resultSet := make(map[string]bool)
			for _, model := range result {
				resultSet[model] = true
			}
			for _, expected := range tt.expectedModels {
				if !resultSet[expected] {
					t.Errorf("SelectModelsForInput(%d, %v) missing expected model: %s",
						tt.estimatedTokens, tt.availableProviders, expected)
				}
			}

			// Verify all returned models are from available providers
			for _, modelName := range result {
				info, err := GetModelInfo(modelName)
				if err != nil {
					t.Errorf("SelectModelsForInput(%d, %v) returned invalid model: %s",
						tt.estimatedTokens, tt.availableProviders, modelName)
					continue
				}

				providerFound := false
				for _, provider := range tt.availableProviders {
					if info.Provider == provider {
						providerFound = true
						break
					}
				}

				if !providerFound {
					t.Errorf("SelectModelsForInput(%d, %v) returned model %s with provider %s not in available providers",
						tt.estimatedTokens, tt.availableProviders, modelName, info.Provider)
				}
			}

			// Verify all models can handle the input with safety margin (1.25x)
			requiredContext := int(float64(tt.estimatedTokens) * 1.25)
			for _, modelName := range result {
				info, err := GetModelInfo(modelName)
				if err != nil {
					continue // Already checked above
				}
				if info.ContextWindow < requiredContext {
					t.Errorf("SelectModelsForInput(%d, %v) returned model %s with insufficient context: %d < %d (required)",
						tt.estimatedTokens, tt.availableProviders, modelName, info.ContextWindow, requiredContext)
				}
			}

			// Verify descending order by context window if requested
			if tt.verifyOrder && len(result) > 1 {
				for i := 0; i < len(result)-1; i++ {
					info1, err1 := GetModelInfo(result[i])
					info2, err2 := GetModelInfo(result[i+1])
					if err1 != nil || err2 != nil {
						continue // Already checked above
					}
					if info1.ContextWindow < info2.ContextWindow {
						t.Errorf("SelectModelsForInput(%d, %v) not properly sorted: "+
							"models[%d]=%s (%d tokens) < models[%d]=%s (%d tokens)",
							tt.estimatedTokens, tt.availableProviders, i, result[i], info1.ContextWindow,
							i+1, result[i+1], info2.ContextWindow)
					}
				}
			}
		})
	}
}

func TestGetLargestContextModel(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name          string
		modelNames    []string
		expectedModel string
	}{
		{
			name:          "empty list returns empty string",
			modelNames:    []string{},
			expectedModel: "",
		},
		{
			name:          "single model returns that model",
			modelNames:    []string{"gpt-5.2"},
			expectedModel: "gpt-5.2",
		},
		{
			name:          "multiple models - grok-4.1-fast has largest context (2M)",
			modelNames:    []string{"gemini-3-flash", "gpt-5.2", "grok-4.1-fast"},
			expectedModel: "grok-4.1-fast",
		},
		{
			name: "mixed context sizes",
			modelNames: []string{
				"claude-opus-4.5",  // 200K
				"gpt-5.2",          // 400K
				"llama-4-maverick", // 1M
				"grok-4.1-fast",    // 2M (largest)
			},
			expectedModel: "grok-4.1-fast",
		},
		{
			name: "models with identical context windows (1M)",
			modelNames: []string{
				"gemini-3-flash",
				"gemini-3-pro",
				"llama-4-maverick",
			},
			expectedModel: "gemini-3-flash", // First one with 1M context wins
		},
		{
			name: "include invalid model names",
			modelNames: []string{
				"invalid-model",
				"gpt-5.2",
				"another-invalid",
				"claude-opus-4.5",
			},
			expectedModel: "gpt-5.2", // 400K vs 200K
		},
		{
			name:          "all invalid model names",
			modelNames:    []string{"invalid-1", "invalid-2", "invalid-3"},
			expectedModel: "",
		},
		{
			name: "comprehensive mix of model types",
			modelNames: []string{
				"claude-opus-4.5",  // 200K
				"gemini-3-flash",   // 1M
				"deepseek-v3.2",    // 163K
				"grok-4.1-fast",    // 2M (largest)
				"llama-4-maverick", // 1M
			},
			expectedModel: "grok-4.1-fast",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GetLargestContextModel(tt.modelNames)

			if result != tt.expectedModel {
				t.Errorf("GetLargestContextModel(%v) = %s, want %s", tt.modelNames, result, tt.expectedModel)
			}

			// Additional verification: if result is non-empty, ensure it's actually the largest
			if result != "" && len(tt.modelNames) > 1 {
				resultInfo, err := GetModelInfo(result)
				if err != nil {
					t.Errorf("GetLargestContextModel(%v) returned invalid model: %s", tt.modelNames, result)
				} else {
					// Check that no other valid model has a larger context
					for _, modelName := range tt.modelNames {
						if modelName == result {
							continue
						}
						info, err := GetModelInfo(modelName)
						if err != nil {
							continue // Skip invalid models
						}
						if info.ContextWindow > resultInfo.ContextWindow {
							t.Errorf("GetLargestContextModel(%v) returned %s (%d tokens) but %s has larger context (%d tokens)",
								tt.modelNames, result, resultInfo.ContextWindow, modelName, info.ContextWindow)
						}
					}
				}
			}

			// Verify result is in the input list (if non-empty)
			if result != "" {
				found := false
				for _, modelName := range tt.modelNames {
					if modelName == result {
						found = true
						break
					}
				}
				if !found {
					t.Errorf("GetLargestContextModel(%v) returned %s which is not in the input list", tt.modelNames, result)
				}
			}
		})
	}
}
