// Package thinktank contains the core application logic for the thinktank tool
package thinktank

import (
	"context"
	"errors"
	"fmt"
	"math/rand/v2"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"time"

	"github.com/misty-step/thinktank/internal/auditlog"
	"github.com/misty-step/thinktank/internal/config"
	"github.com/misty-step/thinktank/internal/llm"
	"github.com/misty-step/thinktank/internal/logutil"
	"github.com/misty-step/thinktank/internal/ratelimit"
	"github.com/misty-step/thinktank/internal/thinktank/interfaces"
	"github.com/misty-step/thinktank/internal/thinktank/orchestrator"
)

// gatherProjectFiles handles setup and context gathering initialization.
// It sets up the output directory and initializes logging for the execution.
func gatherProjectFiles(
	ctx context.Context,
	cliConfig *config.CliConfig,
	logger logutil.LoggerInterface,
	auditLogger auditlog.AuditLogger,
) error {
	// 1. Set up the output directory
	if err := setupOutputDirectory(ctx, cliConfig, logger); err != nil {
		return err
	}

	// 2. Log the start of the Execute operation
	inputs := map[string]interface{}{
		"instructions_file": cliConfig.InstructionsFile,
		"output_dir":        cliConfig.OutputDir,
		"audit_log_file":    cliConfig.AuditLogFile,
		"format":            cliConfig.Format,
		"paths_count":       len(cliConfig.Paths),
		"include":           cliConfig.Include,
		"exclude":           cliConfig.Exclude,
		"exclude_names":     cliConfig.ExcludeNames,
		"dry_run":           cliConfig.DryRun,
		"verbose":           cliConfig.Verbose,
		"model_names":       cliConfig.ModelNames,
		// "confirm_tokens" field removed as part of T032E - token management refactoring
		"log_level": cliConfig.LogLevel,
	}

	if logErr := auditLogger.LogOp(ctx, "ExecuteStart", "InProgress", inputs, nil, nil); logErr != nil {
		logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
	}

	return nil
}

// processFiles handles instruction reading and audit logging.
// It reads instructions from the file and prepares them for processing.
func processFiles(
	ctx context.Context,
	cliConfig *config.CliConfig,
	logger logutil.LoggerInterface,
	auditLogger auditlog.AuditLogger,
) (string, error) {
	// Read instructions from file (skip in dry-run mode if no instructions provided)
	var instructions string
	if cliConfig.InstructionsFile != "" {
		instructionsContent, err := os.ReadFile(cliConfig.InstructionsFile)
		if err != nil {
			logger.ErrorContext(ctx, "Failed to read instructions file %s: %v", cliConfig.InstructionsFile, err)

			// Log the failure to read the instructions file to the audit log
			inputs := map[string]interface{}{"path": cliConfig.InstructionsFile}
			if logErr := auditLogger.LogOp(ctx, "ReadInstructions", "Failure", inputs, nil, err); logErr != nil {
				logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
			}

			return "", fmt.Errorf("%w: failed to read instructions file %s: %v", ErrInvalidInstructions, cliConfig.InstructionsFile, err)
		}
		instructions = string(instructionsContent)
		logger.InfoContext(ctx, "Successfully read instructions from %s", cliConfig.InstructionsFile)
	} else if cliConfig.DryRun {
		// In dry-run mode, allow missing instructions
		instructions = "Dry run mode - no instructions provided"
		logger.InfoContext(ctx, "Dry run mode: proceeding without instructions file")
	} else {
		// This case should not happen due to validation, but handle gracefully
		return "", fmt.Errorf("%w: instructions file is required when not in dry-run mode", ErrInvalidInstructions)
	}

	// Log the successful reading of the instructions file to the audit log
	if logErr := auditLogger.Log(ctx, auditlog.AuditEntry{
		Timestamp: time.Now().UTC(),
		Operation: "ReadInstructions",
		Status:    "Success",
		Inputs: map[string]interface{}{
			"path": cliConfig.InstructionsFile,
		},
		Outputs: map[string]interface{}{
			"content_length": len(instructions),
		},
		Message: "Successfully read instructions file",
	}); logErr != nil {
		logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
	}

	return instructions, nil
}

// generateOutput handles client initialization and orchestrator creation.
// It initializes LLM clients, creates dependencies, and returns a configured orchestrator.
func generateOutput(
	ctx context.Context,
	cliConfig *config.CliConfig,
	logger logutil.LoggerInterface,
	auditLogger auditlog.AuditLogger,
	apiService interfaces.APIService,
	consoleWriter logutil.ConsoleWriter,
) (Orchestrator, error) {
	// Create a reference client for token counting in context gathering
	// Skip LLM client initialization in dry-run mode since no API calls will be made
	var referenceClientLLM llm.LLMClient
	if !cliConfig.DryRun {
		// Pass empty string instead of cliConfig.APIKey to force environment variable lookup
		// This ensures each provider uses its own API key from the appropriate environment variable
		client, err := apiService.InitLLMClient(ctx, "", cliConfig.ModelNames[0], cliConfig.APIEndpoint)
		if err != nil {
			// Check if this is a categorized error to provide better error messages
			if catErr, ok := llm.IsCategorizedError(err); ok {
				category := catErr.Category()

				// Log with category information
				logger.ErrorContext(ctx, "Failed to initialize reference client for context gathering: %v (category: %s)",
					err, category.String())

				// Use error category to give more specific error messages
				switch category {
				case llm.CategoryAuth:
					return nil, fmt.Errorf("%w: API authentication failed for model %s: %v", ErrInvalidAPIKey, cliConfig.ModelNames[0], err)
				case llm.CategoryRateLimit:
					return nil, fmt.Errorf("%w: API rate limit exceeded for model %s: %v", ErrInvalidModelName, cliConfig.ModelNames[0], err)
				case llm.CategoryNotFound:
					return nil, fmt.Errorf("%w: model %s not found or not available: %v", ErrInvalidModelName, cliConfig.ModelNames[0], err)
				case llm.CategoryInputLimit:
					return nil, fmt.Errorf("%w: input token limit exceeded for model %s: %v", ErrInvalidConfiguration, cliConfig.ModelNames[0], err)
				case llm.CategoryContentFiltered:
					return nil, fmt.Errorf("%w: content was filtered by safety settings: %v", ErrInvalidConfiguration, err)
				default:
					return nil, fmt.Errorf("%w: failed to initialize reference client for model %s: %v", ErrInvalidModelName, cliConfig.ModelNames[0], err)
				}
			} else {
				// If not a categorized error, use the standard error handling
				logger.ErrorContext(ctx, "Failed to initialize reference client for context gathering: %v", err)
				return nil, fmt.Errorf("%w: failed to initialize reference client for context gathering: %v", ErrContextGatheringFailed, err)
			}
		}
		referenceClientLLM = client
		defer func() { _ = referenceClientLLM.Close() }()
	}

	// Create context gatherer with LLMClient and ConsoleWriter
	// Note: TokenManager was completely removed as part of tasks T032A through T032D
	contextGatherer := NewContextGatherer(logger, consoleWriter, cliConfig.DryRun, referenceClientLLM, auditLogger)
	fileWriter := NewFileWriter(logger, auditLogger, cliConfig.DirPermissions, cliConfig.FilePermissions)

	// Create rate limiter from configuration
	rateLimiter := ratelimit.NewRateLimiter(
		cliConfig.MaxConcurrentRequests,
		cliConfig.RateLimitRequestsPerMinute,
	)

	// Create adapters for the interfaces
	apiServiceAdapter := &APIServiceAdapter{APIService: apiService}
	fileWriterAdapter := &FileWriterAdapter{FileWriter: fileWriter}

	// Create token counting service for orchestrator
	tokenCountingServiceImpl := NewTokenCountingService()
	tokenCountingService := &TokenCountingServiceAdapter{TokenCountingService: tokenCountingServiceImpl}

	orch := orchestratorConstructor(OrchestratorDeps{
		APIService:           apiServiceAdapter,
		ContextGatherer:      contextGatherer, // Now directly implements interfaces.ContextGatherer
		FileWriter:           fileWriterAdapter,
		AuditLogger:          auditLogger,
		RateLimiter:          rateLimiter,
		Config:               cliConfig,
		Logger:               logger,
		ConsoleWriter:        consoleWriter,
		TokenCountingService: tokenCountingService,
	})

	return orch, nil
}

// writeResults handles orchestrator execution and error processing.
// It runs the orchestrator and converts any errors to thinktank package errors.
func writeResults(ctx context.Context, orch Orchestrator, instructions string) error {
	// Run the orchestrator and handle error conversion
	err := orch.Run(ctx, instructions)

	// Convert orchestrator errors to thinktank package errors if needed
	if err != nil {
		err = wrapOrchestratorErrors(err)
	}

	return err
}

// Execute is the main entry point for the core application logic.
// It handles initial setup, logging, dependency initialization, and orchestration.
func Execute(
	ctx context.Context,
	cliConfig *config.CliConfig,
	logger logutil.LoggerInterface,
	auditLogger auditlog.AuditLogger,
	apiService interfaces.APIService,
	consoleWriter logutil.ConsoleWriter,
) (err error) {
	// Ensure the logger has the context attached
	// This is important for correlation ID propagation
	logger = logger.WithContext(ctx)
	// Use a deferred function to ensure ExecuteEnd is always logged
	defer func() {
		status := "Success"
		if err != nil {
			status = "Failure"
		}

		// Log execution end with appropriate status and any error
		if logErr := auditLogger.LogOp(ctx, "ExecuteEnd", status, nil, nil, err); logErr != nil {
			logger.ErrorContext(ctx, "Failed to write audit log: %v", logErr)
		}
	}()

	// 1. Setup and context gathering initialization
	if err := gatherProjectFiles(ctx, cliConfig, logger, auditLogger); err != nil {
		return err
	}

	// 2. Read instructions and prepare for processing
	instructions, err := processFiles(ctx, cliConfig, logger, auditLogger)
	if err != nil {
		return err
	}

	// 3. Initialize clients and create orchestrator
	orch, err := generateOutput(ctx, cliConfig, logger, auditLogger, apiService, consoleWriter)
	if err != nil {
		return err
	}

	// 4. Execute orchestrator and handle results
	return writeResults(ctx, orch, instructions)
}

// wrapOrchestratorErrors converts orchestrator-specific errors to thinktank package errors.
// This ensures that the caller of the Execute function (usually main.go) can check for
// specific error types without needing to import the orchestrator package directly.
func wrapOrchestratorErrors(err error) error {
	// Import the orchestrator errors package to check for partial failure
	if errors.Is(err, ErrPartialSuccess) {
		// Already wrapped, return as is
		return err
	}

	// Check if this error contains "some models failed" which indicates partial processing failure
	// This avoids direct dependency on orchestrator.ErrPartialProcessingFailure
	if err != nil && strings.Contains(err.Error(), "some models failed during processing") {
		// Wrap with the thinktank ErrPartialSuccess while preserving the original error
		return fmt.Errorf("%w: %v", ErrPartialSuccess, err)
	}

	// Return the original error for other error types
	return err
}

// Note: RunInternal has been removed as part of the refactoring.
// The Execute function now properly handles dependency injection and can be
// used directly for testing by providing appropriate mocks.

// Note: processModel, processModelConcurrently, sanitizeFilename, and saveOutputToFile functions
// have been removed as part of the refactoring. Their functionality has been moved to the
// ModelProcessor in the modelproc package.

// Orchestrator defines the interface for the orchestration component.
// This interface is defined here to allow for testing without introducing import cycles.
type Orchestrator interface {
	Run(ctx context.Context, instructions string) error
}

// Note: The llmToGeminiAdapter has been removed as ContextGatherer now uses llm.LLMClient directly

// orchestratorConstructor is the function used to create an Orchestrator.
// This can be overridden in tests to return a mock orchestrator.
var orchestratorConstructor = func(deps OrchestratorDeps) Orchestrator {
	return orchestrator.NewOrchestrator(deps)
}

// GetOrchestratorConstructor returns the current orchestrator constructor function.
// This is useful for tests that need to temporarily override the constructor.
func GetOrchestratorConstructor() func(deps OrchestratorDeps) Orchestrator {
	return orchestratorConstructor
}

// SetOrchestratorConstructor sets the orchestrator constructor function.
// This is useful for tests that need to temporarily override the constructor.
func SetOrchestratorConstructor(constructor func(deps OrchestratorDeps) Orchestrator) {
	orchestratorConstructor = constructor
}

// incrementalCounter is used to ensure uniqueness of generated names
// even when many names are generated in quick succession
var incrementalCounter uint32 = 0

// generateTimestampedRunName returns a unique directory name in the format thinktank_YYYYMMDD_HHMMSS_NNNNNNNNN
// where NNNNNNNNN is a combination of nanoseconds, random number, and incremental counter to ensure uniqueness.
// This implementation guarantees uniqueness even for many runs that occur within the same millisecond.
func generateTimestampedRunName() string {
	// Get current time
	now := time.Now()

	// Generate timestamp in format YYYYMMDD_HHMMSS
	timestamp := now.Format("20060102_150405")

	// Use multiple strategies to ensure uniqueness:
	// 1. Nanoseconds from the current time (0-999999999)
	// 2. Random number (0-999)
	// 3. Incremental counter (0-999999)

	// Extract nanoseconds (last 3 digits)
	nanos := now.Nanosecond() % 1000

	// Generate a random number
	randNum := rand.IntN(1000)

	// Increment the counter atomically (thread-safe)
	counter := atomic.AddUint32(&incrementalCounter, 1) % 1000

	// Combine all three components for a truly unique value
	// This gives us a billion possibilities (1000 × 1000 × 1000) within the same second
	uniqueNum := (nanos * 1000000) + (randNum * 1000) + int(counter)

	// Combine with prefix and format with leading zeros (9 digits)
	return fmt.Sprintf("thinktank_%s_%09d", timestamp, uniqueNum)
}

// setupOutputDirectory ensures that the output directory is set and exists.
// If outputDir in cliConfig is empty, it generates a unique directory name.
// Note: The logger passed to this function should already have context attached.
func setupOutputDirectory(ctx context.Context, cliConfig *config.CliConfig, logger logutil.LoggerInterface) error {
	if cliConfig.OutputDir == "" {
		// Generate a unique timestamped run name
		runName := generateTimestampedRunName()

		// Get the current working directory
		cwd, err := os.Getwd()
		if err != nil {
			logger.ErrorContext(ctx, "Error getting current working directory: %v", err)
			return fmt.Errorf("%w: error getting current working directory: %v", ErrContextGatheringFailed, err)
		}

		// Set the output directory to the run name in the current working directory
		cliConfig.OutputDir = filepath.Join(cwd, runName)
		logger.InfoContext(ctx, "Generated output directory: %s", cliConfig.OutputDir)
	}

	perms := cliConfig.DirPermissions
	if perms == 0 {
		perms = 0755
	}

	// Ensure the output directory exists
	if err := os.MkdirAll(cliConfig.OutputDir, perms); err != nil {
		logger.ErrorContext(ctx, "Error creating output directory %s: %v", cliConfig.OutputDir, err)
		return fmt.Errorf("%w: error creating output directory %s: %v", ErrInvalidOutputDir, cliConfig.OutputDir, err)
	}

	logger.InfoContext(ctx, "Using output directory: %s", cliConfig.OutputDir)
	return nil
}
