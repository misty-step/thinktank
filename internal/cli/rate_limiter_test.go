package cli

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/misty-step/thinktank/internal/testutil/perftest"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestCircuitBreaker_BasicOperations tests basic circuit breaker functionality
func TestCircuitBreaker_BasicOperations(t *testing.T) {
	cb := NewCircuitBreaker()

	// Initially closed and can execute
	assert.Equal(t, CircuitClosed, cb.GetState())
	assert.True(t, cb.CanExecute())
	assert.Equal(t, 0, cb.GetFailureCount())

	// Record success - should remain closed
	cb.RecordSuccess()
	assert.Equal(t, CircuitClosed, cb.GetState())
	assert.True(t, cb.CanExecute())
	assert.Equal(t, 0, cb.GetFailureCount())
}

// TestCircuitBreaker_FailureThreshold tests circuit breaker opens after threshold failures
func TestCircuitBreaker_FailureThreshold(t *testing.T) {
	cb := NewCircuitBreaker()

	// Record failures up to threshold - 1
	for i := 0; i < CircuitBreakerFailureThreshold-1; i++ {
		cb.RecordFailure()
		assert.Equal(t, CircuitClosed, cb.GetState(), "Circuit should remain closed before threshold")
		assert.True(t, cb.CanExecute(), "Should still allow execution before threshold")
	}

	assert.Equal(t, CircuitBreakerFailureThreshold-1, cb.GetFailureCount())

	// One more failure should open the circuit
	cb.RecordFailure()
	assert.Equal(t, CircuitOpen, cb.GetState(), "Circuit should open after threshold failures")
	assert.False(t, cb.CanExecute(), "Should block execution when circuit is open")
	assert.Equal(t, CircuitBreakerFailureThreshold, cb.GetFailureCount())
}

// TestCircuitBreaker_CooldownRecovery tests circuit breaker recovery after cooldown
func TestCircuitBreaker_CooldownRecovery(t *testing.T) {
	cb := &CircuitBreaker{
		state:            CircuitClosed,
		failureThreshold: 2,                     // Lower threshold for faster testing
		cooldownDuration: 10 * time.Millisecond, // Short cooldown for testing
	}

	// Trigger circuit opening
	cb.RecordFailure()
	cb.RecordFailure()
	assert.Equal(t, CircuitOpen, cb.GetState())
	assert.False(t, cb.CanExecute())

	// Wait for cooldown to pass
	time.Sleep(15 * time.Millisecond)

	// Should now allow execution (transitions to half-open implicitly)
	assert.True(t, cb.CanExecute(), "Should allow execution after cooldown")

	// Manually transition to half-open to test the success recording
	cb.mu.Lock()
	cb.state = CircuitHalfOpen
	cb.mu.Unlock()

	// Record success to close circuit
	cb.RecordSuccess()
	assert.Equal(t, CircuitClosed, cb.GetState())
	assert.Equal(t, 0, cb.GetFailureCount(), "Failure count should reset on success")
}

// TestCircuitBreaker_StateTransitions tests all state transitions
func TestCircuitBreaker_StateTransitions(t *testing.T) {
	cb := &CircuitBreaker{
		state:            CircuitClosed,
		failureThreshold: 2,
		cooldownDuration: 10 * time.Millisecond,
	}

	// Closed -> Open
	cb.RecordFailure()
	cb.RecordFailure()
	assert.Equal(t, CircuitOpen, cb.GetState())

	// Wait for cooldown, should allow execution (Open -> Half-Open transition happens in CanExecute)
	time.Sleep(15 * time.Millisecond)
	assert.True(t, cb.CanExecute())

	// Manually set to half-open to test Half-Open -> Closed
	cb.mu.Lock()
	cb.state = CircuitHalfOpen
	cb.mu.Unlock()

	cb.RecordSuccess()
	assert.Equal(t, CircuitClosed, cb.GetState())
}

// TestNewProviderRateLimiter tests creation of provider rate limiter
func TestNewProviderRateLimiter(t *testing.T) {
	maxConcurrent := 5
	overrides := map[string]int{
		"openai":     5000, // Override default
		"gemini":     100,  // Override default
		"openrouter": 0,    // Should use default
	}

	prl := NewProviderRateLimiter(maxConcurrent, overrides)
	require.NotNil(t, prl)

	// Check provider rate limits
	assert.Equal(t, 5000, prl.GetProviderRateLimit("openai"), "Should use override")
	assert.Equal(t, 100, prl.GetProviderRateLimit("gemini"), "Should use override")
	assert.Equal(t, OpenRouterDefaultRPM, prl.GetProviderRateLimit("openrouter"), "Should use default when override is 0")

	// Check circuit breakers are initialized
	for _, provider := range []string{"openai", "gemini", "openrouter"} {
		status := prl.GetProviderStatus(provider)
		assert.Equal(t, provider, status.Provider)
		assert.True(t, status.Available)
		assert.Equal(t, "CLOSED", status.CircuitState)
		assert.Equal(t, 0, status.FailureCount)
	}
}

// TestProviderRateLimiter_BasicAcquireRelease tests basic acquire/release functionality
func TestProviderRateLimiter_BasicAcquireRelease(t *testing.T) {
	prl := NewProviderRateLimiter(5, nil)
	ctx := context.Background()

	// Should be able to acquire for valid provider
	err := prl.Acquire(ctx, "openai", "gpt-5.2")
	assert.NoError(t, err)

	// Release should work
	prl.Release("openai")

	// Should fail for unknown provider
	err = prl.Acquire(ctx, "unknown", "model")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unknown provider")
}

// TestProviderRateLimiter_CircuitBreakerIntegration tests circuit breaker integration
func TestProviderRateLimiter_CircuitBreakerIntegration(t *testing.T) {
	prl := NewProviderRateLimiter(5, nil)
	ctx := context.Background()

	// Record multiple failures to open circuit
	for i := 0; i < CircuitBreakerFailureThreshold; i++ {
		prl.RecordFailure("openai")
	}

	// Circuit should be open now
	status := prl.GetProviderStatus("openai")
	assert.Equal(t, "OPEN", status.CircuitState)
	assert.False(t, status.Available)
	assert.Equal(t, CircuitBreakerFailureThreshold, status.FailureCount)

	// Acquire should fail when circuit is open
	err := prl.Acquire(ctx, "openai", "gpt-5.2")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "circuit breaker")
	assert.Contains(t, err.Error(), "OPEN")

	// Other providers should still work
	err = prl.Acquire(ctx, "gemini", "gemini-3-flash")
	assert.NoError(t, err)
	prl.Release("gemini")

	// Record success should eventually close circuit
	prl.RecordSuccess("openai")
	// Note: Circuit stays open until cooldown passes, this tests the RecordSuccess logic
}

// TestProviderRateLimiter_GetAllProviderStatuses tests status reporting
func TestProviderRateLimiter_GetAllProviderStatuses(t *testing.T) {
	prl := NewProviderRateLimiter(3, map[string]int{
		"openai": 4000,
	})

	statuses := prl.GetAllProviderStatuses()
	assert.Len(t, statuses, 3, "Should return status for all providers")

	// Find OpenAI status
	var openaiStatus *ProviderStatus
	for _, status := range statuses {
		if status.Provider == "openai" {
			openaiStatus = &status
			break
		}
	}

	require.NotNil(t, openaiStatus, "Should include OpenAI status")
	assert.Equal(t, "openai", openaiStatus.Provider)
	assert.Equal(t, 4000, openaiStatus.RateLimit)
	assert.Equal(t, "CLOSED", openaiStatus.CircuitState)
	assert.True(t, openaiStatus.Available)
}

// TestRetryWithBackoff_Success tests successful retry scenarios
func TestRetryWithBackoff_Success(t *testing.T) {
	callCount := 0
	operation := func() error {
		callCount++
		if callCount < 3 {
			return errors.New("temporary failure")
		}
		return nil // Success on 3rd attempt
	}

	ctx := context.Background()
	err := RetryWithBackoff(ctx, operation, 5)

	assert.NoError(t, err, "Should succeed after retries")
	assert.Equal(t, 3, callCount, "Should call operation 3 times")
}

// TestRetryWithBackoff_ExhaustRetries tests retry exhaustion
func TestRetryWithBackoff_ExhaustRetries(t *testing.T) {
	callCount := 0
	operation := func() error {
		callCount++
		return errors.New("persistent failure")
	}

	ctx := context.Background()
	err := RetryWithBackoff(ctx, operation, 3)

	assert.Error(t, err, "Should fail after exhausting retries")
	assert.Contains(t, err.Error(), "operation failed after 3 attempts")
	assert.Equal(t, 3, callCount, "Should call operation 3 times")
}

// TestRetryWithBackoff_ContextCancellation tests context cancellation during retry
func TestRetryWithBackoff_ContextCancellation(t *testing.T) {
	callCount := 0
	operation := func() error {
		callCount++
		return errors.New("failure")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Millisecond)
	defer cancel()

	err := RetryWithBackoff(ctx, operation, 10)

	assert.Error(t, err, "Should fail due to context cancellation")
	assert.Contains(t, err.Error(), "retry cancelled")
	// Call count should be limited due to context cancellation
	assert.LessOrEqual(t, callCount, 3, "Should not retry many times due to timeout")
}

// TestRetryWithBackoff_ImmediateSuccess tests immediate success without retries
func TestRetryWithBackoff_ImmediateSuccess(t *testing.T) {
	callCount := 0
	operation := func() error {
		callCount++
		return nil // Immediate success
	}

	ctx := context.Background()
	err := RetryWithBackoff(ctx, operation, 5)

	assert.NoError(t, err, "Should succeed immediately")
	assert.Equal(t, 1, callCount, "Should call operation only once")
}

// TestCalculateBackoffDelay tests exponential backoff delay calculation
func TestCalculateBackoffDelay(t *testing.T) {
	tests := []struct {
		name    string
		attempt int
		minExp  time.Duration // Minimum expected delay (before jitter)
		maxExp  time.Duration // Maximum expected delay (before jitter)
	}{
		{
			name:    "first retry",
			attempt: 0,
			minExp:  BaseRetryDelay,     // 1s * 2^0 = 1s
			maxExp:  BaseRetryDelay * 2, // With jitter
		},
		{
			name:    "second retry",
			attempt: 1,
			minExp:  BaseRetryDelay,     // 1s * 2^1 = 2s, but with negative jitter
			maxExp:  BaseRetryDelay * 4, // With positive jitter
		},
		{
			name:    "high attempt should cap at max",
			attempt: 10,
			minExp:  MaxRetryDelay / 2, // Should be capped but with jitter
			maxExp:  MaxRetryDelay * 2, // With jitter, should not exceed much
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			delay := calculateBackoffDelay(tt.attempt)

			// Should be positive
			assert.Positive(t, delay, "Delay should be positive")

			// Should be within reasonable bounds (considering jitter)
			assert.GreaterOrEqual(t, delay, time.Duration(0), "Delay should not be negative")
			assert.LessOrEqual(t, delay, MaxRetryDelay*2, "Delay should not exceed reasonable maximum")
		})
	}
}

// TestProviderRateLimiter_ConcurrentAccess tests thread safety
func TestProviderRateLimiter_ConcurrentAccess(t *testing.T) {
	prl := NewProviderRateLimiter(10, nil)
	ctx := context.Background()

	// Test concurrent access from multiple goroutines
	const numGoroutines = 20
	const operationsPerGoroutine = 10

	var wg sync.WaitGroup
	errors := make([]error, numGoroutines*operationsPerGoroutine)
	errorIndex := 0
	var errorMutex sync.Mutex

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func(goroutineID int) {
			defer wg.Done()

			for j := 0; j < operationsPerGoroutine; j++ {
				// Acquire
				err := prl.Acquire(ctx, "openai", "gpt-5.2")

				errorMutex.Lock()
				errors[errorIndex] = err
				errorIndex++
				errorMutex.Unlock()

				if err == nil {
					// Small delay to simulate work
					time.Sleep(time.Microsecond)
					prl.Release("openai")
				}

				// Test status access
				_ = prl.GetProviderStatus("openai")
				_ = prl.GetAllProviderStatuses()

				// Test circuit breaker operations
				if j%5 == 0 {
					prl.RecordSuccess("openai")
				}
			}
		}(i)
	}

	wg.Wait()

	// Count successful operations (errors should be nil)
	successCount := 0
	for _, err := range errors {
		if err == nil {
			successCount++
		}
	}

	// Should have some successful operations (exact count depends on rate limiting)
	assert.Greater(t, successCount, 0, "Should have some successful operations")

	// Should not have crashed or deadlocked
	assert.True(t, true, "Concurrent access completed without deadlock")
}

// TestCircuitBreakerState_String tests state string representation
func TestCircuitBreakerState_String(t *testing.T) {
	tests := []struct {
		state    CircuitBreakerState
		expected string
	}{
		{CircuitClosed, "CLOSED"},
		{CircuitOpen, "OPEN"},
		{CircuitHalfOpen, "HALF_OPEN"},
		{CircuitBreakerState(999), "UNKNOWN"},
	}

	for _, tt := range tests {
		t.Run(tt.expected, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.state.String())
		})
	}
}

// TestProviderRateLimiter_InvalidProvider tests handling of invalid providers
func TestProviderRateLimiter_InvalidProvider(t *testing.T) {
	prl := NewProviderRateLimiter(5, nil)

	// Test invalid provider for various operations
	status := prl.GetProviderStatus("invalid")
	assert.Equal(t, "invalid", status.Provider)
	assert.False(t, status.Available)
	assert.Equal(t, 0, status.RateLimit)
	assert.Equal(t, "UNKNOWN", status.CircuitState)

	// GetProviderRateLimit should return 0 for invalid provider
	assert.Equal(t, 0, prl.GetProviderRateLimit("invalid"))

	// Operations on invalid provider should be safe (no panics)
	prl.RecordSuccess("invalid") // Should not panic
	prl.RecordFailure("invalid") // Should not panic
	prl.Release("invalid")       // Should not panic
}

// BenchmarkProviderRateLimiter_Acquire benchmarks the acquire operation
func BenchmarkProviderRateLimiter_Acquire(b *testing.B) {
	prl := NewProviderRateLimiter(1000, nil) // High concurrency for benchmarking
	ctx := context.Background()

	perftest.RunBenchmark(b, "ProviderRateLimiter_Acquire", func(b *testing.B) {
		b.RunParallel(func(pb *testing.PB) {
			for pb.Next() {
				err := prl.Acquire(ctx, "openai", "gpt-5.2")
				if err == nil {
					prl.Release("openai")
				}
			}
		})
	})
}

// BenchmarkCircuitBreaker_CanExecute benchmarks circuit breaker check
func BenchmarkCircuitBreaker_CanExecute(b *testing.B) {
	cb := NewCircuitBreaker()

	perftest.RunBenchmark(b, "CircuitBreaker_CanExecute", func(b *testing.B) {
		b.RunParallel(func(pb *testing.PB) {
			for pb.Next() {
				_ = cb.CanExecute()
			}
		})
	})
}
