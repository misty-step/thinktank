// Package cli provides the command-line interface logic for the thinktank tool
package cli

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/misty-step/thinktank/internal/config"
	"github.com/misty-step/thinktank/internal/logutil"
	"github.com/misty-step/thinktank/internal/thinktank"
)

// MockTokenCountingService provides a test implementation of TokenCountingService
type MockTokenCountingService struct {
	models []string
}

func (m *MockTokenCountingService) CountTokens(ctx context.Context, req thinktank.TokenCountingRequest) (thinktank.TokenCountingResult, error) {
	return thinktank.TokenCountingResult{
		TotalTokens:       1000,
		InstructionTokens: 100,
		FileTokens:        900,
	}, nil
}

func (m *MockTokenCountingService) CountTokensForModel(ctx context.Context, req thinktank.TokenCountingRequest, modelName string) (thinktank.ModelTokenCountingResult, error) {
	return thinktank.ModelTokenCountingResult{
		TokenCountingResult: thinktank.TokenCountingResult{
			TotalTokens:       1000,
			InstructionTokens: 100,
			FileTokens:        900,
		},
		ModelName: modelName,
	}, nil
}

func (m *MockTokenCountingService) GetCompatibleModels(ctx context.Context, req thinktank.TokenCountingRequest, providers []string) ([]thinktank.ModelCompatibility, error) {
	var result []thinktank.ModelCompatibility
	for _, model := range m.models {
		result = append(result, thinktank.ModelCompatibility{
			ModelName:    model,
			IsCompatible: true,
		})
	}
	return result, nil
}

func TestSetupConfiguration(t *testing.T) {
	tests := []struct {
		name               string
		simplifiedConfig   *SimplifiedConfig
		tokenServiceModels []string
		expectedModelNames []string
		expectedVerbose    bool
		expectedLogLevel   logutil.LogLevel
		expectedDryRun     bool
		expectedQuiet      bool
		expectedNoProgress bool
		expectedJsonLogs   bool
		wantErr            bool
	}{
		{
			name: "basic configuration with core council models",
			simplifiedConfig: &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       "src/",
				Flags:            FlagDryRun,
			},
			tokenServiceModels: []string{"gemini-3-flash"}, // Token service models are not used; core council is returned
			expectedModelNames: []string{"gemini-3.1-pro", "claude-sonnet-4-6", "gpt-5.2", "grok-4.1-fast", "deepseek-v3.2", "glm-5", "moonshotai/kimi-k2.5", "minimax-m2.5"},
			expectedVerbose:    false,
			expectedLogLevel:   logutil.InfoLevel,
			expectedDryRun:     true,
			expectedQuiet:      false,
			expectedNoProgress: false,
			expectedJsonLogs:   false,
			wantErr:            false,
		},
		{
			name: "verbose flag sets debug log level",
			simplifiedConfig: &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       "src/",
				Flags:            FlagVerbose,
			},
			tokenServiceModels: []string{"gemini-3-flash"}, // Token service models are not used; core council is returned
			expectedModelNames: []string{"gemini-3.1-pro", "claude-sonnet-4-6", "gpt-5.2", "grok-4.1-fast", "deepseek-v3.2", "glm-5", "moonshotai/kimi-k2.5", "minimax-m2.5"},
			expectedVerbose:    true,
			expectedLogLevel:   logutil.DebugLevel,
			expectedDryRun:     false,
			expectedQuiet:      false,
			expectedNoProgress: false,
			expectedJsonLogs:   false,
			wantErr:            false,
		},
		{
			name: "debug flag sets debug log level",
			simplifiedConfig: &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       "src/",
				Flags:            FlagDebug,
			},
			tokenServiceModels: []string{"gemini-3-flash"}, // Token service models are not used; core council is returned
			expectedModelNames: []string{"gemini-3.1-pro", "claude-sonnet-4-6", "gpt-5.2", "grok-4.1-fast", "deepseek-v3.2", "glm-5", "moonshotai/kimi-k2.5", "minimax-m2.5"},
			expectedVerbose:    false,
			expectedLogLevel:   logutil.DebugLevel,
			expectedDryRun:     false,
			expectedQuiet:      false,
			expectedNoProgress: false,
			expectedJsonLogs:   false,
			wantErr:            false,
		},
		{
			name: "all flags enabled",
			simplifiedConfig: &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       "src/ tests/",
				Flags:            FlagDryRun | FlagVerbose | FlagQuiet | FlagNoProgress | FlagJsonLogs | FlagDebug,
			},
			tokenServiceModels: []string{"gemini-3-flash"}, // Token service models are not used; core council is returned
			expectedModelNames: []string{"gemini-3.1-pro", "claude-sonnet-4-6", "gpt-5.2", "grok-4.1-fast", "deepseek-v3.2", "glm-5", "moonshotai/kimi-k2.5", "minimax-m2.5"},
			expectedVerbose:    true,
			expectedLogLevel:   logutil.DebugLevel, // Both verbose and debug set debug level
			expectedDryRun:     true,
			expectedQuiet:      true,
			expectedNoProgress: true,
			expectedJsonLogs:   true,
			wantErr:            false,
		},
		{
			name: "core council models with no special flags",
			simplifiedConfig: &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       "src/",
				Flags:            0, // No flags
			},
			tokenServiceModels: []string{"gemini-3-flash", "gpt-5.2"}, // Token service models are not used; core council is returned
			expectedModelNames: []string{"gemini-3.1-pro", "claude-sonnet-4-6", "gpt-5.2", "grok-4.1-fast", "deepseek-v3.2", "glm-5", "moonshotai/kimi-k2.5", "minimax-m2.5"},
			expectedVerbose:    false,
			expectedLogLevel:   logutil.InfoLevel,
			expectedDryRun:     false,
			expectedQuiet:      false,
			expectedNoProgress: false,
			expectedJsonLogs:   false,
			wantErr:            false,
		},
		{
			name: "synthesis flag with core council",
			simplifiedConfig: &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       "src/",
				Flags:            FlagSynthesis,
			},
			tokenServiceModels: []string{"gemini-3-flash"}, // Token service models are not used; core council is returned
			expectedModelNames: []string{"gemini-3.1-pro", "claude-sonnet-4-6", "gpt-5.2", "grok-4.1-fast", "deepseek-v3.2", "glm-5", "moonshotai/kimi-k2.5", "minimax-m2.5"},
			expectedVerbose:    false,
			expectedLogLevel:   logutil.InfoLevel,
			expectedDryRun:     false,
			expectedQuiet:      false,
			expectedNoProgress: false,
			expectedJsonLogs:   false,
			wantErr:            false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create mock token service
			mockTokenService := &MockTokenCountingService{
				models: tt.tokenServiceModels,
			}

			// Call setupConfiguration
			result, err := setupConfiguration(tt.simplifiedConfig, mockTokenService)

			// Check error expectation
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			require.NotNil(t, result)

			// Verify basic configuration fields
			assert.Equal(t, tt.simplifiedConfig.InstructionsFile, result.InstructionsFile)
			assert.Equal(t, tt.expectedModelNames, result.ModelNames)
			assert.Equal(t, tt.expectedVerbose, result.Verbose)
			assert.Equal(t, tt.expectedLogLevel, result.LogLevel)
			assert.Equal(t, tt.expectedDryRun, result.DryRun)
			assert.Equal(t, tt.expectedQuiet, result.Quiet)
			assert.Equal(t, tt.expectedNoProgress, result.NoProgress)
			assert.Equal(t, tt.expectedJsonLogs, result.JsonLogs)

			// Verify target paths are properly split
			expectedPaths := []string{}
			if tt.simplifiedConfig.TargetPath != "" {
				expectedPaths = []string{"src/"}
				if tt.simplifiedConfig.TargetPath == "src/ tests/" {
					expectedPaths = []string{"src/", "tests/"}
				}
			}
			assert.Equal(t, expectedPaths, result.TargetPaths)

			// Verify default values are set correctly
			assert.Equal(t, "", result.OutputDir) // Should be empty, set later
			assert.Equal(t, config.DefaultTimeout, result.Timeout)
			assert.Equal(t, config.DefaultFormat, result.Format)
			assert.Equal(t, config.DefaultExcludes, result.Exclude)
			assert.Equal(t, config.DefaultExcludeNames, result.ExcludeNames)

			// Verify synthesis model logic
			if len(tt.expectedModelNames) > 1 || tt.simplifiedConfig.HasFlag(FlagSynthesis) {
				assert.Equal(t, "gemini-3.1-pro", result.SynthesisModel)
			} else {
				assert.Equal(t, "", result.SynthesisModel)
			}
		})
	}
}

func TestSetupConfigurationEdgeCases(t *testing.T) {
	tests := []struct {
		name             string
		simplifiedConfig *SimplifiedConfig
		tokenService     thinktank.TokenCountingService
		wantErr          bool
		expectedError    string
	}{
		{
			name: "empty instructions file",
			simplifiedConfig: &SimplifiedConfig{
				InstructionsFile: "",
				TargetPath:       "src/",
				Flags:            0,
			},
			tokenService: &MockTokenCountingService{models: []string{"gemini-3-flash"}},
			wantErr:      false, // setupConfiguration doesn't validate file existence
		},
		{
			name: "empty target path",
			simplifiedConfig: &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       "",
				Flags:            0,
			},
			tokenService: &MockTokenCountingService{models: []string{"gemini-3-flash"}},
			wantErr:      false, // setupConfiguration doesn't validate path existence
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := setupConfiguration(tt.simplifiedConfig, tt.tokenService)

			if tt.wantErr {
				assert.Error(t, err)
				if tt.expectedError != "" {
					assert.Contains(t, err.Error(), tt.expectedError)
				}
				return
			}

			require.NoError(t, err)
			require.NotNil(t, result)
		})
	}
}

func TestSetupConfigurationTargetPathParsing(t *testing.T) {
	tests := []struct {
		name          string
		targetPath    string
		expectedPaths []string
	}{
		{
			name:          "single path",
			targetPath:    "src/",
			expectedPaths: []string{"src/"},
		},
		{
			name:          "multiple paths",
			targetPath:    "src/ tests/ docs/",
			expectedPaths: []string{"src/", "tests/", "docs/"},
		},
		{
			name:          "single file",
			targetPath:    "main.go",
			expectedPaths: []string{"main.go"},
		},
		{
			name:          "mixed files and directories",
			targetPath:    "main.go src/ test.go",
			expectedPaths: []string{"main.go", "src/", "test.go"},
		},
		{
			name:          "empty path",
			targetPath:    "",
			expectedPaths: []string{},
		},
		{
			name:          "spaces only",
			targetPath:    "   ",
			expectedPaths: []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			simplifiedConfig := &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       tt.targetPath,
				Flags:            0,
			}

			mockTokenService := &MockTokenCountingService{
				models: []string{"gemini-3-flash"},
			}

			result, err := setupConfiguration(simplifiedConfig, mockTokenService)
			require.NoError(t, err)
			require.NotNil(t, result)

			assert.Equal(t, tt.expectedPaths, result.TargetPaths)
		})
	}
}

func TestSetupConfigurationLogLevelPrecedence(t *testing.T) {
	tests := []struct {
		name          string
		flags         uint8
		expectedLevel logutil.LogLevel
	}{
		{
			name:          "no flags - default info level",
			flags:         0,
			expectedLevel: logutil.InfoLevel,
		},
		{
			name:          "verbose flag - debug level",
			flags:         FlagVerbose,
			expectedLevel: logutil.DebugLevel,
		},
		{
			name:          "debug flag - debug level",
			flags:         FlagDebug,
			expectedLevel: logutil.DebugLevel,
		},
		{
			name:          "both verbose and debug - debug level",
			flags:         FlagVerbose | FlagDebug,
			expectedLevel: logutil.DebugLevel,
		},
		{
			name:          "other flags - info level",
			flags:         FlagDryRun | FlagQuiet | FlagNoProgress,
			expectedLevel: logutil.InfoLevel,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			simplifiedConfig := &SimplifiedConfig{
				InstructionsFile: "test.md",
				TargetPath:       "src/",
				Flags:            tt.flags,
			}

			mockTokenService := &MockTokenCountingService{
				models: []string{"gemini-3-flash"},
			}

			result, err := setupConfiguration(simplifiedConfig, mockTokenService)
			require.NoError(t, err)
			require.NotNil(t, result)

			assert.Equal(t, tt.expectedLevel, result.LogLevel)
		})
	}
}
