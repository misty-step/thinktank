// Package modelproc provides model processing functionality for the thinktank tool.
// It encapsulates the logic for interacting with AI models, managing tokens,
// writing outputs, and logging operations.
package modelproc

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/misty-step/thinktank/internal/auditlog"
	"github.com/misty-step/thinktank/internal/config"
	"github.com/misty-step/thinktank/internal/llm"
	"github.com/misty-step/thinktank/internal/logutil"
	"github.com/misty-step/thinktank/internal/models"
	"github.com/misty-step/thinktank/internal/thinktank/interfaces"
)

// APIService defines the interface for API-related operations
type APIService interface {
	// InitLLMClient initializes and returns a provider-agnostic LLM client
	InitLLMClient(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error)

	// GetModelParameters retrieves parameter values from the models package for a given model
	GetModelParameters(ctx context.Context, modelName string) (map[string]interface{}, error)

	// GetModelDefinition retrieves the full model definition
	GetModelDefinition(ctx context.Context, modelName string) (*models.ModelInfo, error)

	// GetModelTokenLimits retrieves token limits from the models package for a given model
	GetModelTokenLimits(ctx context.Context, modelName string) (contextWindow, maxOutputTokens int32, err error)

	// ProcessLLMResponse processes a provider-agnostic response and extracts content
	ProcessLLMResponse(result *llm.ProviderResult) (string, error)

	// IsEmptyResponseError checks if an error is related to empty API responses
	IsEmptyResponseError(err error) bool

	// IsSafetyBlockedError checks if an error is related to safety filters
	IsSafetyBlockedError(err error) bool

	// GetErrorDetails extracts detailed information from an error
	GetErrorDetails(err error) string
}

// ModelProcessor handles all interactions with AI models including initialization,
// token management, request generation, response processing, and output handling.
type ModelProcessor struct {
	// Dependencies
	apiService  APIService
	fileWriter  interfaces.FileWriter
	auditLogger auditlog.AuditLogger
	logger      logutil.LoggerInterface
	config      *config.CliConfig
	// timeAfter is used for retry delays; defaults to time.After, injectable for tests.
	timeAfter func(time.Duration) <-chan time.Time
}

// NewProcessor creates a new ModelProcessor with all required dependencies.
// Note: TokenManagers are created per-model in the Process method.
// This is necessary to avoid import cycles and to handle the multi-model architecture.
func NewProcessor(
	apiService APIService,
	fileWriter interfaces.FileWriter,
	auditLogger auditlog.AuditLogger,
	logger logutil.LoggerInterface,
	config *config.CliConfig,
) *ModelProcessor {
	return &ModelProcessor{
		apiService:  apiService,
		fileWriter:  fileWriter,
		auditLogger: auditLogger,
		logger:      logger,
		config:      config,
		timeAfter:   time.After,
	}
}

// Process handles the entire model processing workflow for a single model.
// It implements the logic from the previous processModel/processModelConcurrently functions,
// including initialization, token checking, generation, response processing, and output saving.
// When used with the synthesis feature, this method also returns the generated content as a string,
// allowing the orchestrator to collect outputs from multiple models for synthesis.
//
// Returns:
//   - The generated content as a string, which can be used for synthesis
//   - Any error encountered during processing
func (p *ModelProcessor) Process(ctx context.Context, modelName string, stitchedPrompt string) (string, error) {
	p.logger.InfoContext(ctx, "Processing model: %s", modelName)

	// 1. Initialize model-specific LLM client
	llmClient, err := p.apiService.InitLLMClient(ctx, p.config.APIKey, modelName, p.config.APIEndpoint)
	if err != nil {
		// Use the APIService interface for consistent error detail extraction
		errorDetails := p.apiService.GetErrorDetails(err)
		p.logger.ErrorContext(ctx, "Error creating LLM client for model %s: %s", modelName, errorDetails)
		return "", llm.Wrap(ErrModelInitializationFailed, "", fmt.Sprintf("failed to initialize API client for model %s: %v", modelName, err), llm.CategoryInvalidRequest)
	}

	// BUGFIX: Ensure llmClient is not nil before attempting to close it
	// CAUSE: There was a race condition in tests where client could be nil
	//        when concurrent tests interact with rate limiting, leading to nil pointer dereference
	// FIX: Add safety check in defer to prevent a panic if client is nil for any reason
	defer func() {
		if llmClient != nil {
			_ = llmClient.Close()
		}
	}()

	// Token validation has been completely removed as part of tasks T032A and T032B
	// We now rely on provider APIs to enforce their own token limits

	// 3. Generate content with this model
	p.logger.InfoContext(ctx, "Generating output with model %s...", modelName)

	// Log the start of content generation
	generateStartTime := time.Now()
	inputs := map[string]interface{}{
		"model_name":    modelName,
		"prompt_length": len(stitchedPrompt),
	}
	if logErr := p.auditLogger.LogOp(ctx, "GenerateContent", "InProgress", inputs, nil, nil); logErr != nil {
		p.logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
	}

	// Get model parameters from the APIService
	params, err := p.apiService.GetModelParameters(ctx, modelName)
	if err != nil {
		p.logger.DebugContext(ctx, "Failed to get model parameters for %s: %v. Using defaults.", modelName, err)
		// Continue with empty parameters if there's an error
		params = make(map[string]interface{})
	}

	// Log parameters being used (at debug level)
	if len(params) > 0 {
		p.logger.DebugContext(ctx, "Using model parameters for %s:", modelName)
		for k, v := range params {
			p.logger.DebugContext(ctx, "  %s: %v", k, v)
		}
	}

	// Generate content with parameters, retrying on transient failures.
	result, err := p.generateContentWithRetry(ctx, llmClient, stitchedPrompt, params, modelName)

	// Calculate duration in milliseconds
	generateDurationMs := time.Since(generateStartTime).Milliseconds()

	if err != nil {
		// Propagate context errors directly so callers can inspect ctx.Err().
		if ctxErr := ctx.Err(); ctxErr != nil {
			return "", ctxErr
		}

		p.logger.ErrorContext(ctx, "Generation failed for model %s", modelName)

		// Get detailed error information using APIService
		errorDetails := p.apiService.GetErrorDetails(err)
		p.logger.ErrorContext(ctx, "Error generating content with model %s: %s", modelName, errorDetails)

		// Add generation duration to inputs for logging
		inputs["duration_ms"] = generateDurationMs

		// Log the content generation failure
		if logErr := p.auditLogger.LogOp(ctx, "GenerateContent", "Failure", inputs, nil, err); logErr != nil {
			p.logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
		}

		return "", llm.Wrap(ErrModelProcessingFailed, "", fmt.Sprintf("output generation failed for model %s: %v", modelName, err), llm.CategoryInvalidRequest)
	}

	// Log successful content generation
	inputs["duration_ms"] = generateDurationMs
	outputs := map[string]interface{}{
		"finish_reason":      result.FinishReason,
		"has_safety_ratings": len(result.SafetyInfo) > 0,
	}
	if logErr := p.auditLogger.LogOp(ctx, "GenerateContent", "Success", inputs, outputs, nil); logErr != nil {
		p.logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
	}

	// 4. Process API response
	generatedOutput, err := p.apiService.ProcessLLMResponse(result)
	if err != nil {
		// Get detailed error information
		errorDetails := p.apiService.GetErrorDetails(err)

		// Provide specific error messages based on error type
		if p.apiService.IsEmptyResponseError(err) {
			p.logger.ErrorContext(ctx, "Received empty or invalid response from API for model %s", modelName)
			p.logger.ErrorContext(ctx, "Error details: %s", errorDetails)
			return "", llm.Wrap(ErrEmptyModelResponse, "", fmt.Sprintf("failed to process API response for model %s due to empty content: %v", modelName, err), llm.CategoryInvalidRequest)
		} else if p.apiService.IsSafetyBlockedError(err) {
			p.logger.ErrorContext(ctx, "Content was blocked by safety filters for model %s", modelName)
			p.logger.ErrorContext(ctx, "Error details: %s", errorDetails)
			return "", llm.Wrap(ErrContentFiltered, "", fmt.Sprintf("failed to process API response for model %s due to safety restrictions: %v", modelName, err), llm.CategoryContentFiltered)
		} else if catErr, isCat := llm.IsCategorizedError(err); isCat {
			// Use the new error categorization for more specific messages
			switch catErr.Category() {
			case llm.CategoryContentFiltered:
				p.logger.ErrorContext(ctx, "Content was filtered by safety settings for model %s", modelName)
				p.logger.ErrorContext(ctx, "Error details: %s", errorDetails)
				return "", llm.Wrap(ErrContentFiltered, "", fmt.Sprintf("failed to process API response for model %s due to content filtering: %v", modelName, err), llm.CategoryContentFiltered)
			case llm.CategoryRateLimit:
				p.logger.ErrorContext(ctx, "Rate limit exceeded while processing response for model %s", modelName)
				p.logger.ErrorContext(ctx, "Error details: %s", errorDetails)
				return "", llm.Wrap(ErrModelRateLimited, "", fmt.Sprintf("failed to process API response for model %s due to rate limiting: %v", modelName, err), llm.CategoryRateLimit)
			case llm.CategoryInputLimit:
				p.logger.ErrorContext(ctx, "Input limit exceeded during response processing for model %s", modelName)
				p.logger.ErrorContext(ctx, "Error details: %s", errorDetails)
				return "", llm.Wrap(ErrModelTokenLimitExceeded, "", fmt.Sprintf("failed to process API response for model %s due to input limits: %v", modelName, err), llm.CategoryInputLimit)
			default:
				// Other categorized errors
				p.logger.ErrorContext(ctx, "Error processing response for model %s (%s category)", modelName, catErr.Category())
				p.logger.ErrorContext(ctx, "Error details: %s", errorDetails)
				return "", llm.Wrap(ErrInvalidModelResponse, "", fmt.Sprintf("failed to process API response for model %s (%s error): %v", modelName, catErr.Category(), err), catErr.Category())
			}
		} else {
			// Generic API error handling
			p.logger.ErrorContext(ctx, "Error processing API response for model %s", modelName)
			return "", llm.Wrap(ErrInvalidModelResponse, "", fmt.Sprintf("failed to process API response for model %s: %v", modelName, err), llm.CategoryInvalidRequest)
		}
	}
	contentLength := len(generatedOutput)
	p.logger.InfoContext(ctx, "Output generated successfully with model %s (content length: %d characters)",
		modelName, contentLength)

	// 5. Sanitize model name for use in filename
	sanitizedModelName := SanitizeFilename(modelName)

	// 6. Construct output file path
	outputFilePath := filepath.Join(p.config.OutputDir, sanitizedModelName+".md")

	// 7. Save the output to file
	if err := p.saveOutputToFile(ctx, outputFilePath, generatedOutput); err != nil {
		return "", llm.Wrap(ErrOutputWriteFailed, "", fmt.Sprintf("failed to save output for model %s: %v", modelName, err), llm.CategoryInvalidRequest)
	}

	p.logger.InfoContext(ctx, "Successfully processed model: %s", modelName)
	return generatedOutput, nil
}

// generateContentWithRetry calls llmClient.GenerateContent with up to maxAttempts retries
// for transient failures. It uses EstimatedWaitTime from ExtractRecoveryInformation when
// available, falling back to exponential backoff. Non-retryable errors are returned
// immediately. Context cancellation during a wait is respected.
func (p *ModelProcessor) generateContentWithRetry(
	ctx context.Context,
	llmClient llm.LLMClient,
	prompt string,
	params map[string]interface{},
	modelName string,
) (*llm.ProviderResult, error) {
	const maxAttempts = 3
	const baseWait = 2 * time.Second

	var lastErr error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		result, err := llmClient.GenerateContent(ctx, prompt, params)
		if err == nil {
			if attempt > 1 {
				p.logger.InfoContext(ctx, "Model %s succeeded on attempt %d/%d after retries",
					modelName, attempt, maxAttempts)
			}
			return result, nil
		}
		lastErr = err
		recovery := llm.ExtractRecoveryInformation(err)
		if !recovery.RetryPossible || attempt == maxAttempts {
			return nil, err
		}
		waitTime := recovery.EstimatedWaitTime
		if waitTime == 0 {
			waitTime = baseWait * time.Duration(1<<uint(attempt-1))
		}
		p.logger.InfoContext(ctx, "Retrying model %s (attempt %d/%d) after %v: %v",
			modelName, attempt, maxAttempts, waitTime, err)
		select {
		case <-p.timeAfter(waitTime):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return nil, lastErr
}

// SanitizeFilename replaces characters that are not valid in filenames
// with safe alternatives to ensure filenames are valid across different operating systems.
func SanitizeFilename(filename string) string {
	// Replace slashes and other problematic characters with hyphens
	replacer := strings.NewReplacer(
		"/", "-",
		"\\", "-",
		":", "-",
		"*", "-",
		"?", "-",
		"\"", "-",
		"'", "-", // Also replace single quotes
		"<", "-",
		">", "-",
		"|", "-",
		" ", "_", // Replace spaces with underscores for better readability
	)
	return replacer.Replace(filename)
}

// saveOutputToFile is a helper method that saves the generated output to a file
// and includes audit logging around the file writing operation.
func (p *ModelProcessor) saveOutputToFile(ctx context.Context, outputFilePath, content string) error {
	// Log the start of output saving
	saveStartTime := time.Now()
	inputs := map[string]interface{}{
		"output_path":    outputFilePath,
		"content_length": len(content),
	}
	if logErr := p.auditLogger.LogOp(ctx, "SaveOutput", "InProgress", inputs, nil, nil); logErr != nil {
		p.logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
	}

	// Save output file
	p.logger.InfoContext(ctx, "Writing output to %s...", outputFilePath)
	err := p.fileWriter.SaveToFile(ctx, content, outputFilePath)

	// Calculate duration in milliseconds
	saveDurationMs := time.Since(saveStartTime).Milliseconds()

	if err != nil {
		// Log failure to save output
		p.logger.ErrorContext(ctx, "Error saving output to file %s: %v", outputFilePath, err)

		inputs["duration_ms"] = saveDurationMs
		if logErr := p.auditLogger.LogOp(ctx, "SaveOutput", "Failure", inputs, nil, err); logErr != nil {
			p.logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
		}

		return llm.Wrap(ErrOutputWriteFailed, "", fmt.Sprintf("error saving output to file %s: %v", outputFilePath, err), llm.CategoryServer)
	}

	// Log successful saving of output
	inputs["duration_ms"] = saveDurationMs
	outputs := map[string]interface{}{
		"content_length": len(content),
	}
	if logErr := p.auditLogger.LogOp(ctx, "SaveOutput", "Success", inputs, outputs, nil); logErr != nil {
		p.logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
	}

	p.logger.InfoContext(ctx, "Output successfully generated and saved to %s", outputFilePath)
	return nil
}
