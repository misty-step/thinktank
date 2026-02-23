package modelproc_test

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	"github.com/misty-step/thinktank/internal/config"
	"github.com/misty-step/thinktank/internal/llm"
	"github.com/misty-step/thinktank/internal/thinktank/modelproc"
)

// instantTimer returns a channel that fires immediately, replacing time.After in retry tests.
func instantTimer(_ time.Duration) <-chan time.Time {
	ch := make(chan time.Time, 1)
	ch <- time.Now()
	return ch
}

// newRetryProcessor creates a processor with instantTimer for fast retry tests.
func newRetryProcessor(mockAPI *mockAPIService) *modelproc.ModelProcessor {
	cfg := config.NewDefaultCliConfig()
	cfg.APIKey = "test-key"
	cfg.OutputDir = "/tmp/test-output"
	p := modelproc.NewProcessor(mockAPI, &mockFileWriter{}, &mockAuditLogger{}, newNoOpLogger(), cfg)
	p.SetTimeAfterForTest(instantTimer)
	return p
}

// retryableErr returns a categorized LLM error with RetryPossible=true (CategoryNetwork → 30s wait).
func retryableErr(msg string) error {
	return llm.Wrap(errors.New(msg), "", msg, llm.CategoryNetwork)
}

// nonRetryableErr returns a CategoryAuth error (RetryPossible=false).
func nonRetryableErr(msg string) error {
	return llm.Wrap(errors.New(msg), "", msg, llm.CategoryAuth)
}

// nonTransientCategorizedErr returns a categorized error that should not be retried.
func nonTransientCategorizedErr(msg string) error {
	return llm.Wrap(errors.New(msg), "", msg, llm.CategoryContentFiltered)
}

func TestGenerateContentWithRetry_SucceedOnSecondAttempt(t *testing.T) {
	var callCount atomic.Int32
	mockAPI := &mockAPIService{
		initLLMClientFunc: func(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
			return &mockLLMClient{
				generateContentFunc: func(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
					n := callCount.Add(1)
					if n == 1 {
						return nil, retryableErr("transient network error")
					}
					return &llm.ProviderResult{Content: "success"}, nil
				},
			}, nil
		},
		processLLMResponseFunc: func(result *llm.ProviderResult) (string, error) {
			return result.Content, nil
		},
	}

	p := newRetryProcessor(mockAPI)
	content, err := p.Process(context.Background(), "test-model", "prompt")

	if err != nil {
		t.Fatalf("expected success on retry, got error: %v", err)
	}
	if content != "success" {
		t.Errorf("expected content %q, got %q", "success", content)
	}
	if callCount.Load() != 2 {
		t.Errorf("expected 2 GenerateContent calls, got %d", callCount.Load())
	}
}

func TestGenerateContentWithRetry_ExhaustsMaxAttempts(t *testing.T) {
	var callCount atomic.Int32
	mockAPI := &mockAPIService{
		initLLMClientFunc: func(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
			return &mockLLMClient{
				generateContentFunc: func(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
					callCount.Add(1)
					return nil, retryableErr("network error")
				},
			}, nil
		},
	}

	p := newRetryProcessor(mockAPI)
	_, err := p.Process(context.Background(), "test-model", "prompt")

	if err == nil {
		t.Fatal("expected error after exhausting retries, got nil")
	}
	if callCount.Load() != 3 {
		t.Errorf("expected 3 GenerateContent calls (maxAttempts), got %d", callCount.Load())
	}
}

func TestGenerateContentWithRetry_NoRetryOnAuthError(t *testing.T) {
	var callCount atomic.Int32
	mockAPI := &mockAPIService{
		initLLMClientFunc: func(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
			return &mockLLMClient{
				generateContentFunc: func(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
					callCount.Add(1)
					return nil, nonRetryableErr("auth failed")
				},
			}, nil
		},
	}

	p := newRetryProcessor(mockAPI)
	_, err := p.Process(context.Background(), "test-model", "prompt")

	if err == nil {
		t.Fatal("expected error for auth failure, got nil")
	}
	if callCount.Load() != 1 {
		t.Errorf("expected exactly 1 call (no retry on auth), got %d", callCount.Load())
	}
}

func TestGenerateContentWithRetry_NoRetryOnNonTransientCategorizedError(t *testing.T) {
	var callCount atomic.Int32
	mockAPI := &mockAPIService{
		initLLMClientFunc: func(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
			return &mockLLMClient{
				generateContentFunc: func(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
					callCount.Add(1)
					return nil, nonTransientCategorizedErr("filtered content")
				},
			}, nil
		},
	}

	p := newRetryProcessor(mockAPI)
	_, err := p.Process(context.Background(), "test-model", "prompt")
	if err == nil {
		t.Fatal("expected error for non-transient categorized failure, got nil")
	}
	if callCount.Load() != 1 {
		t.Errorf("expected exactly 1 call (no retry on non-transient error), got %d", callCount.Load())
	}
}

func TestGenerateContentWithRetry_PreservesRetryableErrorCategory(t *testing.T) {
	mockAPI := &mockAPIService{
		initLLMClientFunc: func(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
			return &mockLLMClient{
				generateContentFunc: func(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
					return nil, retryableErr("network error")
				},
			}, nil
		},
	}

	p := newRetryProcessor(mockAPI)
	_, err := p.Process(context.Background(), "test-model", "prompt")
	if err == nil {
		t.Fatal("expected error after exhausting retries, got nil")
	}

	catErr, ok := llm.IsCategorizedError(err)
	if !ok {
		t.Fatalf("expected categorized error, got: %v", err)
	}
	if catErr.Category() != llm.CategoryNetwork {
		t.Errorf("expected category %s, got %s", llm.CategoryNetwork, catErr.Category())
	}
}

func TestGenerateContentWithRetry_ContextCancelledDuringWait(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())

	var callCount atomic.Int32
	mockAPI := &mockAPIService{
		initLLMClientFunc: func(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
			return &mockLLMClient{
				generateContentFunc: func(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
					callCount.Add(1)
					return nil, retryableErr("transient error")
				},
			}, nil
		},
	}

	// Timer that cancels the context instead of firing, simulating ctx.Done() during wait.
	blockingTimer := func(d time.Duration) <-chan time.Time {
		cancel()
		return make(chan time.Time) // never fires
	}

	p := newRetryProcessor(mockAPI)
	p.SetTimeAfterForTest(blockingTimer)

	_, err := p.Process(ctx, "test-model", "prompt")

	if err == nil {
		t.Fatal("expected error from context cancellation, got nil")
	}
	if !errors.Is(err, context.Canceled) {
		t.Errorf("expected context.Canceled, got: %v", err)
	}
	if callCount.Load() != 1 {
		t.Errorf("expected 1 attempt before cancellation, got %d", callCount.Load())
	}
}

func TestGenerateContentWithRetry_RateLimitUsesEstimatedWait(t *testing.T) {
	var callCount atomic.Int32
	var recordedWait time.Duration

	mockAPI := &mockAPIService{
		initLLMClientFunc: func(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
			return &mockLLMClient{
				generateContentFunc: func(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
					n := callCount.Add(1)
					if n == 1 {
						return nil, llm.Wrap(errors.New("rate limited"), "", "rate limited", llm.CategoryRateLimit)
					}
					return &llm.ProviderResult{Content: "ok"}, nil
				},
			}, nil
		},
		processLLMResponseFunc: func(result *llm.ProviderResult) (string, error) {
			return result.Content, nil
		},
	}

	recordingTimer := func(d time.Duration) <-chan time.Time {
		recordedWait = d
		ch := make(chan time.Time, 1)
		ch <- time.Now()
		return ch
	}

	p := newRetryProcessor(mockAPI)
	p.SetTimeAfterForTest(recordingTimer)

	_, err := p.Process(context.Background(), "test-model", "prompt")
	if err != nil {
		t.Fatalf("expected success, got: %v", err)
	}

	// ExtractRecoveryInformation sets EstimatedWaitTime=60s for CategoryRateLimit.
	const expectedWait = 60 * time.Second
	if recordedWait != expectedWait {
		t.Errorf("expected wait %v for rate limit, got %v", expectedWait, recordedWait)
	}
}

func TestGenerateContentWithRetry_NetworkUsesEstimatedWait(t *testing.T) {
	var callCount atomic.Int32
	var recordedWait time.Duration

	mockAPI := &mockAPIService{
		initLLMClientFunc: func(ctx context.Context, apiKey, modelName, apiEndpoint string) (llm.LLMClient, error) {
			return &mockLLMClient{
				generateContentFunc: func(ctx context.Context, prompt string, params map[string]interface{}) (*llm.ProviderResult, error) {
					n := callCount.Add(1)
					if n == 1 {
						return nil, llm.Wrap(errors.New("network blip"), "", "network blip", llm.CategoryNetwork)
					}
					return &llm.ProviderResult{Content: "ok"}, nil
				},
			}, nil
		},
		processLLMResponseFunc: func(result *llm.ProviderResult) (string, error) {
			return result.Content, nil
		},
	}

	recordingTimer := func(d time.Duration) <-chan time.Time {
		recordedWait = d
		ch := make(chan time.Time, 1)
		ch <- time.Now()
		return ch
	}

	p := newRetryProcessor(mockAPI)
	p.SetTimeAfterForTest(recordingTimer)

	_, err := p.Process(context.Background(), "test-model", "prompt")
	if err != nil {
		t.Fatalf("expected success, got: %v", err)
	}

	// ExtractRecoveryInformation sets EstimatedWaitTime=30s for CategoryNetwork.
	const expectedWait = 30 * time.Second
	if recordedWait != expectedWait {
		t.Errorf("expected wait %v for network error, got %v", expectedWait, recordedWait)
	}
}
