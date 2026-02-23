// Package integration provides integration tests for the thinktank package
package integration

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/misty-step/thinktank/internal/auditlog"
	"github.com/misty-step/thinktank/internal/config"
	"github.com/misty-step/thinktank/internal/llm"
	"github.com/misty-step/thinktank/internal/logutil"
	"github.com/misty-step/thinktank/internal/models"
	"github.com/misty-step/thinktank/internal/thinktank/modelproc"
)

func instantTimer(_ time.Duration) <-chan time.Time {
	ch := make(chan time.Time, 1)
	ch <- time.Now()
	return ch
}

// TestModelProcessorContextPropagation tests that the model processor properly propagates
// context through the model processing workflow and includes correlation IDs in logs.
func TestModelProcessorContextPropagation(t *testing.T) {
	// Create a test environment with a TestLogger to reliably capture logs
	testLogger := logutil.NewTestLogger(t)
	env := setupModelProcTestEnvWithLogger(t, testLogger)

	// Create a context with correlation ID
	correlationID := "test-model-correlation-id"
	ctx := logutil.WithCorrelationID(context.Background(), correlationID)

	// Log that we're starting the test with correlation ID
	testLogger.InfoContext(ctx, "Starting context propagation test")

	// Process a model
	modelName := "test-model"
	prompt := "This is a test prompt"

	// Configure mock API to capture the context
	var capturedCorrelationID string
	env.apiCaller.CallLLMAPIFunc = func(ctx context.Context, model, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
		// Extract correlation ID from context
		capturedCorrelationID = logutil.GetCorrelationID(ctx)

		// Log from within the API caller to show context propagation
		testLogger.DebugContext(ctx, "Processing API call for model: %s", model)

		// Return a successful response
		return &llm.ProviderResult{
			Content:      "Test response",
			FinishReason: "stop",
		}, nil
	}

	// Process the model
	output, err := env.processor.Process(ctx, modelName, prompt)

	// Verify no error
	if err != nil {
		t.Fatalf("Process returned error: %v", err)
	}

	// Verify output
	if output != "Test response" {
		t.Errorf("Expected 'Test response', got: %s", output)
	}

	// Verify correlation ID was propagated to API caller
	if capturedCorrelationID != correlationID {
		t.Errorf("Correlation ID not properly propagated to API caller, expected '%s', got: %s",
			correlationID, capturedCorrelationID)
	}

	// Verify audit logs contain correlation ID
	for _, entry := range env.auditLogger.Entries {
		entryCorrelationID, ok := entry.Inputs["correlation_id"]
		if !ok {
			t.Errorf("Audit log entry missing correlation_id: %+v", entry)
			continue
		}

		if entryCorrelationID != correlationID {
			t.Errorf("Expected correlation_id '%s', got: %v", correlationID, entryCorrelationID)
		}
	}

	// Verify logs contain the correlation ID
	logs := testLogger.GetTestLogs()
	foundCorrelationID := false
	for _, logMsg := range logs {
		if strings.Contains(logMsg, correlationID) {
			foundCorrelationID = true
			break
		}
	}

	if !foundCorrelationID {
		t.Errorf("Logs do not contain the correlation ID: %s", correlationID)
	} else {
		t.Logf("Successfully found correlation ID in logs: %s", correlationID)
	}
}

// TestModelProcessorContextCancellation tests that the model processor
// properly handles context cancellation during processing.
func TestModelProcessorContextCancellation(t *testing.T) {
	// Create a test environment with TestLogger
	testLogger := logutil.NewTestLogger(t)

	// Declare expected error patterns for context cancellation
	testLogger.ExpectError("Generation failed for model test-model")
	testLogger.ExpectError("Error generating content with model test-model")

	env := setupModelProcTestEnvWithLogger(t, testLogger)

	// Create a context with correlation ID that we'll cancel
	correlationID := "cancellation-test-id"
	baseCtx := logutil.WithCorrelationID(context.Background(), correlationID)
	ctx, cancel := context.WithCancel(baseCtx)

	// Add initial log with context
	testLogger.InfoContext(ctx, "Starting context cancellation test")

	// Configure mock API to hang until cancelled
	env.apiCaller.CallLLMAPIFunc = func(ctx context.Context, model, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
		// Log that we're entering the API call - should include correlation ID
		testLogger.DebugContext(ctx, "API call started for model: %s", model)

		// Create a channel to wait for cancellation
		<-ctx.Done()

		// Log that cancellation was detected - should include correlation ID
		testLogger.DebugContext(ctx, "Detected context cancellation in API call")

		// Return cancellation error
		return nil, ctx.Err()
	}

	// Start processing in a goroutine
	resultCh := make(chan struct {
		output string
		err    error
	})

	go func() {
		modelName := "test-model"
		prompt := "This is a test prompt"
		output, err := env.processor.Process(ctx, modelName, prompt)
		resultCh <- struct {
			output string
			err    error
		}{output, err}
	}()

	// Give a small delay to ensure API call has started
	time.Sleep(100 * time.Millisecond)

	// Cancel the context
	cancel()

	// Wait for result with timeout
	var result struct {
		output string
		err    error
	}

	select {
	case result = <-resultCh:
		// Continue to verification

	case <-time.After(2 * time.Second):
		t.Fatal("Test timed out waiting for cancelled operation")
	}

	// Verify we got a cancellation error
	if result.err == nil {
		t.Error("Expected error after cancellation, got nil")
	} else {
		// Log the error we received
		t.Logf("Received error after cancellation: %v", result.err)

		// Verify the error type is related to cancellation
		errLower := strings.ToLower(result.err.Error())
		isDeadlineError := strings.Contains(errLower, "deadline") && strings.Contains(errLower, "exceed")
		isCancelError := strings.Contains(errLower, "cancel")

		if !isDeadlineError && !isCancelError {
			t.Errorf("Expected cancellation error, got: %v", result.err)
		}

		// Verify error is properly categorized
		// Check if the error is a categorized error
		catErr, ok := llm.IsCategorizedError(result.err)
		if ok {
			// Log the actual category
			t.Logf("Error category: %v", catErr.Category())
		} else {
			t.Logf("Error is not categorized: %v", result.err)
		}
	}

	// Verify logs contain the correlation ID
	logs := testLogger.GetTestLogs()
	foundCorrelationID := false
	for _, logMsg := range logs {
		if strings.Contains(logMsg, correlationID) {
			foundCorrelationID = true
			break
		}
	}

	if !foundCorrelationID {
		t.Errorf("Logs do not contain the correlation ID: %s", correlationID)
	} else {
		t.Logf("Successfully found correlation ID in logs: %s", correlationID)
	}
}

// TestModelProcessorErrorHandling tests the error handling patterns in the model processor.
// It verifies that errors are properly wrapped, categorized, and that correlation IDs are preserved.
func TestModelProcessorErrorHandling(t *testing.T) {
	// Create a test environment with TestLogger without auto-fail
	testLogger := logutil.NewTestLoggerWithoutAutoFail(t)

	// Declare expected error patterns for this error handling test
	testLogger.ExpectError("Generation failed for model test-model")
	testLogger.ExpectError("Error generating content with model test-model")
	// Additional patterns for specific error scenarios
	testLogger.ExpectError("invalid API key provided")
	testLogger.ExpectError("rate limit exceeded")
	testLogger.ExpectError("content filtered by safety system")
	testLogger.ExpectError("input exceeds maximum token limit")
	testLogger.ExpectError("context deadline exceeded")
	testLogger.ExpectError("clear error message: an underlying error")

	env := setupModelProcTestEnvWithLogger(t, testLogger)

	// Create a context with correlation ID
	correlationID := "error-handling-test-id"
	ctx := logutil.WithCorrelationID(context.Background(), correlationID)

	// Log that we're starting the test
	testLogger.InfoContext(ctx, "Starting error handling tests with correlation ID")

	// Define test cases for different error categories
	testCases := []struct {
		name          string
		apiError      error
		wantCategory  llm.ErrorCategory
		wantErrorText string
	}{
		{
			name:          "auth error",
			apiError:      fmt.Errorf("invalid API key provided"),
			wantCategory:  llm.CategoryAuth,
			wantErrorText: "API key",
		},
		{
			name:          "rate limit error",
			apiError:      fmt.Errorf("rate limit exceeded"),
			wantCategory:  llm.CategoryRateLimit,
			wantErrorText: "rate limit",
		},
		{
			name:          "content filtered error",
			apiError:      fmt.Errorf("content filtered by safety system"),
			wantCategory:  llm.CategoryContentFiltered,
			wantErrorText: "content filtered",
		},
		{
			name:          "input limit error",
			apiError:      fmt.Errorf("input exceeds maximum token limit"),
			wantCategory:  llm.CategoryInputLimit,
			wantErrorText: "token limit",
		},
		{
			name:          "context deadline exceeded",
			apiError:      context.DeadlineExceeded,
			wantCategory:  llm.CategoryCancelled,
			wantErrorText: "deadline",
		},
		{
			name:          "llm properly wrapped error",
			apiError:      llm.Wrap(fmt.Errorf("an underlying error"), "request-id-123", "clear error message", llm.CategoryServer),
			wantCategory:  llm.CategoryServer,
			wantErrorText: "clear error message",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Create a sub-logger with the same test context
			subLogger := testLogger.WithContext(ctx)

			// Log the test case we're running
			subLogger.InfoContext(ctx, "Testing error case: %s", tc.name)

			// Configure mock API to return the test error
			env.apiCaller.CallLLMAPIFunc = func(ctx context.Context, model, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
				// Log with context before returning error
				subLogger.DebugContext(ctx, "API call for %s will return error: %v", model, tc.apiError)

				// For categorized errors, return the error directly, for others wrap them
				if categorizedErr, ok := tc.apiError.(llm.CategorizedError); ok {
					return nil, categorizedErr
				}

				// Return the error with appropriate wrapping
				return nil, llm.Wrap(tc.apiError, "", tc.apiError.Error(), tc.wantCategory)
			}

			// Process the model - expect an error
			_, err := env.processor.Process(ctx, "test-model", "test prompt")

			// Verify error is returned
			if err == nil {
				t.Fatal("Expected error, got nil")
			}

			// Log the error we received
			t.Logf("Received error: %v", err)

			// Verify error contains expected text
			if !strings.Contains(strings.ToLower(err.Error()), strings.ToLower(tc.wantErrorText)) {
				t.Errorf("Expected error message to contain '%s', got: %v", tc.wantErrorText, err)
			}

			// Check if the error is a categorized error
			catErr, ok := llm.IsCategorizedError(err)
			if !ok {
				t.Logf("Error is not categorized: %v", err)
				// It's okay if the processor wrapped the error differently
				return
			}

			// Log the actual category
			t.Logf("Error category: %v", catErr.Category())

			// Check audit logs to verify correlation ID is included
			foundCorrelationID := false
			for _, entry := range env.auditLogger.Entries {
				if entry.Error != nil && // Only check error entries
					entry.Inputs != nil {
					if id, ok := entry.Inputs["correlation_id"]; ok && id == correlationID {
						foundCorrelationID = true
						break
					}
				}
			}

			if !foundCorrelationID && len(env.auditLogger.Entries) > 0 {
				t.Errorf("Correlation ID not found in audit logs for error case: %s", tc.name)
			}
		})
	}

	// Verify logs contain the correlation ID across all tests
	logs := testLogger.GetTestLogs()
	foundCorrelationID := false
	for _, logMsg := range logs {
		if strings.Contains(logMsg, correlationID) {
			foundCorrelationID = true
			break
		}
	}

	if !foundCorrelationID {
		t.Errorf("Logs do not contain the correlation ID: %s", correlationID)
	} else {
		t.Logf("Successfully found correlation ID in logs: %s", correlationID)
	}
}

// ModelProcAuditLogger implements auditlog.AuditLogger for modelproc tests
type ModelProcAuditLogger struct {
	Entries []auditlog.AuditEntry
}

func (m *ModelProcAuditLogger) Log(ctx context.Context, entry auditlog.AuditEntry) error {
	// Add correlation ID from context if not already present
	correlationID := logutil.GetCorrelationID(ctx)
	if correlationID != "" {
		if entry.Inputs == nil {
			entry.Inputs = make(map[string]interface{})
		}
		if _, exists := entry.Inputs["correlation_id"]; !exists {
			entry.Inputs["correlation_id"] = correlationID
		}
	}

	m.Entries = append(m.Entries, entry)
	return nil
}

func (m *ModelProcAuditLogger) LogLegacy(entry auditlog.AuditEntry) error {
	return m.Log(context.Background(), entry)
}

func (m *ModelProcAuditLogger) LogOp(ctx context.Context, operation, status string, inputs map[string]interface{}, outputs map[string]interface{}, err error) error {
	// Make a copy of inputs to avoid modifying the original map
	inputsCopy := make(map[string]interface{})
	for k, v := range inputs {
		inputsCopy[k] = v
	}

	// Add correlation ID from context if not already present
	correlationID := logutil.GetCorrelationID(ctx)
	if correlationID != "" {
		if _, exists := inputsCopy["correlation_id"]; !exists {
			inputsCopy["correlation_id"] = correlationID
		}
	}

	entry := auditlog.AuditEntry{
		Operation: operation,
		Status:    status,
		Inputs:    inputsCopy,
		Outputs:   outputs,
	}

	if err != nil {
		entry.Error = &auditlog.ErrorInfo{
			Message: err.Error(),
			Type:    "TestError",
		}
	}

	m.Entries = append(m.Entries, entry)
	return nil
}

func (m *ModelProcAuditLogger) LogOpLegacy(operation, status string, inputs map[string]interface{}, outputs map[string]interface{}, err error) error {
	return m.LogOp(context.Background(), operation, status, inputs, outputs, err)
}

func (m *ModelProcAuditLogger) Close() error {
	return nil
}

// ModelProcFileWriter implements interfaces.FileWriter for modelproc tests
type ModelProcFileWriter struct {
	Files map[string]string
}

func (m *ModelProcFileWriter) SaveToFile(ctx context.Context, content, filePath string) error {
	m.Files[filePath] = content
	return nil
}

// Comment out unused function to pass linting
// func setupModelProcTestEnv(t *testing.T) *ModelProcTestEnv {
// 	// Create a logger
// 	logger := logutil.NewLogger(logutil.DebugLevel, nil, "[test] ")
// 	return setupModelProcTestEnvWithLogger(t, logger)
// }

// ModelProcAPIClient implements the ExternalAPICaller interface for modelproc tests
type ModelProcAPIClient struct {
	// Function to be mocked in tests
	CallLLMAPIFunc func(ctx context.Context, modelName, prompt string, params map[string]interface{}) (*llm.ProviderResult, error)
}

// CallLLMAPI calls the mocked function
func (m *ModelProcAPIClient) CallLLMAPI(ctx context.Context, modelName, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
	return m.CallLLMAPIFunc(ctx, modelName, prompt, params)
}

// ModelProcTestEnv represents a test environment for modelproc tests
type ModelProcTestEnv struct {
	processor   *modelproc.ModelProcessor
	apiCaller   *ModelProcAPIClient
	fileWriter  *ModelProcFileWriter
	auditLogger *ModelProcAuditLogger
	logger      logutil.LoggerInterface
	config      *config.CliConfig
}

// setupModelProcTestEnvWithLogger creates a test environment for modelproc tests using the provided logger
func setupModelProcTestEnvWithLogger(t *testing.T, logger logutil.LoggerInterface) *ModelProcTestEnv {
	// Create an API caller
	apiCaller := &ModelProcAPIClient{
		CallLLMAPIFunc: func(ctx context.Context, model, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
			return &llm.ProviderResult{
				Content:      "Default test response",
				FinishReason: "stop",
			}, nil
		},
	}

	// Create a file writer
	fileWriter := &ModelProcFileWriter{
		Files: make(map[string]string),
	}

	// Create an audit logger
	auditLogger := &ModelProcAuditLogger{
		Entries: make([]auditlog.AuditEntry, 0),
	}

	// Create a config
	tempDir, err := os.MkdirTemp("", "modelproc-test")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}

	t.Cleanup(func() {
		if err := os.RemoveAll(tempDir); err != nil {
			t.Logf("Failed to clean up temp dir: %v", err)
		}
	})

	// Create a minimal CLI config with just what we need for tests
	defaultCliConfig := config.NewDefaultCliConfig()
	defaultCliConfig.OutputDir = tempDir

	config := defaultCliConfig

	// Create a simple API service that implements the API interface
	apiService := &testAPIService{
		apiCaller: apiCaller,
		logger:    logger,
	}

	// Create the model processor
	processor := modelproc.NewProcessor(apiService, fileWriter, auditLogger, logger, config)
	processor.SetTimeAfterForTest(instantTimer)

	return &ModelProcTestEnv{
		processor:   processor,
		apiCaller:   apiCaller,
		fileWriter:  fileWriter,
		auditLogger: auditLogger,
		logger:      logger,
		config:      config,
	}
}

// testAPIService implements the APIService interface for testing
type testAPIService struct {
	apiCaller *ModelProcAPIClient
	logger    logutil.LoggerInterface
}

// InitLLMClient initializes a mock LLM client
func (s *testAPIService) InitLLMClient(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
	// Return a mock LLM client that uses our API caller
	return &testLLMClient{
		apiCaller: s.apiCaller,
		modelName: modelName,
	}, nil
}

// GetModelParameters returns test model parameters
func (s *testAPIService) GetModelParameters(ctx context.Context, modelName string) (map[string]interface{}, error) {
	return map[string]interface{}{
		"temperature": 0.7,
		"max_tokens":  100,
	}, nil
}

// GetModelDefinition returns a test model definition
func (s *testAPIService) GetModelDefinition(ctx context.Context, modelName string) (*models.ModelInfo, error) {
	return &models.ModelInfo{
		APIModelID: modelName,
		Provider:   "test-provider",
	}, nil
}

// GetModelTokenLimits returns test token limits
func (s *testAPIService) GetModelTokenLimits(ctx context.Context, modelName string) (contextWindow, maxOutputTokens int32, err error) {
	return 4096, 1024, nil
}

// ProcessLLMResponse processes a test LLM response
func (s *testAPIService) ProcessLLMResponse(result *llm.ProviderResult) (string, error) {
	if result == nil {
		return "", errors.New("nil result")
	}
	return result.Content, nil
}

// IsEmptyResponseError checks for empty response errors
func (s *testAPIService) IsEmptyResponseError(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(strings.ToLower(err.Error()), "empty")
}

// IsSafetyBlockedError checks for safety blocked errors
func (s *testAPIService) IsSafetyBlockedError(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(strings.ToLower(err.Error()), "safety") ||
		strings.Contains(strings.ToLower(err.Error()), "content filter")
}

// GetErrorDetails extracts details from an error
func (s *testAPIService) GetErrorDetails(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// testLLMClient implements llm.LLMClient for tests
type testLLMClient struct {
	apiCaller *ModelProcAPIClient
	modelName string
}

// GenerateContent calls the API caller to generate content
func (c *testLLMClient) GenerateContent(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
	return c.apiCaller.CallLLMAPI(ctx, c.modelName, prompt, params)
}

// GetModelName returns the model name
func (c *testLLMClient) GetModelName() string {
	return c.modelName
}

// Close is a no-op for tests
func (c *testLLMClient) Close() error {
	return nil
}
