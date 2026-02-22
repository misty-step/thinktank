// Package cli provides rate limiting functionality with circuit breaker patterns
// and provider-specific intelligent defaults for the thinktank CLI tool.
package cli

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"sync"
	"time"

	"github.com/misty-step/thinktank/internal/models"
	"github.com/misty-step/thinktank/internal/ratelimit"
)

// Provider-specific rate limit constants - matches models.GetProviderDefaultRateLimit()
const (
	OpenAIDefaultRPM     = 3000 // OpenAI has high rate limits for paid accounts
	GeminiDefaultRPM     = 60   // Gemini has moderate rate limits
	OpenRouterDefaultRPM = 20   // OpenRouter varies by model, conservative default
)

// Circuit breaker configuration constants
const (
	CircuitBreakerFailureThreshold = 5                // Number of failures before circuit opens
	CircuitBreakerCooldownDuration = 30 * time.Second // Time to wait before retrying
	MaxRetryAttempts               = 3                // Maximum number of retry attempts
	BaseRetryDelay                 = 1 * time.Second  // Base delay for exponential backoff
	MaxRetryDelay                  = 30 * time.Second // Maximum delay for exponential backoff
	JitterFactor                   = 0.1              // Jitter factor for randomization (10%)
)

// CircuitBreakerState represents the state of a circuit breaker
type CircuitBreakerState int

const (
	// CircuitClosed - normal operation, requests are allowed
	CircuitClosed CircuitBreakerState = iota
	// CircuitOpen - circuit is open, requests are blocked
	CircuitOpen
	// CircuitHalfOpen - limited requests allowed to test if service is back
	CircuitHalfOpen
)

// String returns a string representation of the circuit breaker state
func (s CircuitBreakerState) String() string {
	switch s {
	case CircuitClosed:
		return "CLOSED"
	case CircuitOpen:
		return "OPEN"
	case CircuitHalfOpen:
		return "HALF_OPEN"
	default:
		return "UNKNOWN"
	}
}

// CircuitBreaker implements the circuit breaker pattern for provider fault tolerance
type CircuitBreaker struct {
	mu               sync.RWMutex
	state            CircuitBreakerState
	failureCount     int
	lastFailureTime  time.Time
	nextRetryTime    time.Time
	failureThreshold int
	cooldownDuration time.Duration
}

// NewCircuitBreaker creates a new circuit breaker with default settings
func NewCircuitBreaker() *CircuitBreaker {
	return &CircuitBreaker{
		state:            CircuitClosed,
		failureThreshold: CircuitBreakerFailureThreshold,
		cooldownDuration: CircuitBreakerCooldownDuration,
	}
}

// CanExecute returns true if the circuit breaker allows the request to proceed
func (cb *CircuitBreaker) CanExecute() bool {
	cb.mu.RLock()
	defer cb.mu.RUnlock()

	switch cb.state {
	case CircuitClosed:
		return true
	case CircuitOpen:
		// Check if enough time has passed to attempt a retry
		return time.Now().After(cb.nextRetryTime)
	case CircuitHalfOpen:
		return true
	default:
		return false
	}
}

// RecordSuccess records a successful operation and may close the circuit
func (cb *CircuitBreaker) RecordSuccess() {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	// Reset failure count on any success
	cb.failureCount = 0

	// If circuit is half-open, close it completely
	if cb.state == CircuitHalfOpen {
		cb.state = CircuitClosed
	}
}

// RecordFailure records a failed operation and may open the circuit
func (cb *CircuitBreaker) RecordFailure() {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	cb.failureCount++
	cb.lastFailureTime = time.Now()

	if cb.failureCount >= cb.failureThreshold {
		cb.state = CircuitOpen
		cb.nextRetryTime = time.Now().Add(cb.cooldownDuration)
	}
}

// GetState returns the current state of the circuit breaker (thread-safe)
func (cb *CircuitBreaker) GetState() CircuitBreakerState {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	return cb.state
}

// GetFailureCount returns the current failure count (thread-safe)
func (cb *CircuitBreaker) GetFailureCount() int {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	return cb.failureCount
}

// ProviderRateLimiter provides provider-specific rate limiting with circuit breaker
type ProviderRateLimiter struct {
	mu              sync.RWMutex
	rateLimiters    map[string]*ratelimit.RateLimiter
	circuitBreakers map[string]*CircuitBreaker
	providerLimits  map[string]int // Cache of provider rate limits
}

// NewProviderRateLimiter creates a new provider-specific rate limiter
func NewProviderRateLimiter(maxConcurrent int, providerOverrides map[string]int) *ProviderRateLimiter {
	prl := &ProviderRateLimiter{
		rateLimiters:    make(map[string]*ratelimit.RateLimiter),
		circuitBreakers: make(map[string]*CircuitBreaker),
		providerLimits:  make(map[string]int),
	}

	// Initialize rate limiters for each provider
	providers := []string{"openai", "gemini", "openrouter"}
	for _, provider := range providers {
		// Get rate limit: override > provider default
		rateLimit := models.GetProviderDefaultRateLimit(provider)
		if override, exists := providerOverrides[provider]; exists && override > 0 {
			rateLimit = override
		}

		// Create rate limiter and circuit breaker for this provider
		prl.rateLimiters[provider] = ratelimit.NewRateLimiter(maxConcurrent, rateLimit)
		prl.circuitBreakers[provider] = NewCircuitBreaker()
		prl.providerLimits[provider] = rateLimit
	}

	return prl
}

// Acquire attempts to acquire rate limiting permission for the given provider and model
// Returns error if circuit breaker is open or rate limit is exceeded
func (prl *ProviderRateLimiter) Acquire(ctx context.Context, provider, modelName string) error {
	// Get circuit breaker for this provider
	circuitBreaker := prl.getCircuitBreaker(provider)
	if circuitBreaker == nil {
		return fmt.Errorf("unknown provider: %s", provider)
	}

	// Check if circuit breaker allows execution
	if !circuitBreaker.CanExecute() {
		state := circuitBreaker.GetState()
		failureCount := circuitBreaker.GetFailureCount()
		return fmt.Errorf("circuit breaker for provider %s is %s (failures: %d)",
			provider, state.String(), failureCount)
	}

	// If circuit is half-open, transition it to half-open state
	if circuitBreaker.GetState() == CircuitOpen {
		prl.transitionToHalfOpen(provider)
	}

	// Acquire rate limit permission
	rateLimiter := prl.getRateLimiter(provider)
	if rateLimiter == nil {
		return fmt.Errorf("no rate limiter configured for provider: %s", provider)
	}

	// Use model name for per-model rate limiting
	return rateLimiter.Acquire(ctx, modelName)
}

// Release releases the rate limiting permission for the given provider
func (prl *ProviderRateLimiter) Release(provider string) {
	rateLimiter := prl.getRateLimiter(provider)
	if rateLimiter != nil {
		rateLimiter.Release()
	}
}

// RecordSuccess records a successful operation for the provider's circuit breaker
func (prl *ProviderRateLimiter) RecordSuccess(provider string) {
	circuitBreaker := prl.getCircuitBreaker(provider)
	if circuitBreaker != nil {
		circuitBreaker.RecordSuccess()
	}
}

// RecordFailure records a failed operation for the provider's circuit breaker
func (prl *ProviderRateLimiter) RecordFailure(provider string) {
	circuitBreaker := prl.getCircuitBreaker(provider)
	if circuitBreaker != nil {
		circuitBreaker.RecordFailure()
	}
}

// GetProviderStatus returns status information for a provider
func (prl *ProviderRateLimiter) GetProviderStatus(provider string) ProviderStatus {
	prl.mu.RLock()
	defer prl.mu.RUnlock()

	circuitBreaker := prl.circuitBreakers[provider]
	if circuitBreaker == nil {
		return ProviderStatus{
			Provider:     provider,
			Available:    false,
			RateLimit:    0,
			CircuitState: "UNKNOWN",
			FailureCount: 0,
		}
	}

	return ProviderStatus{
		Provider:     provider,
		Available:    circuitBreaker.CanExecute(),
		RateLimit:    prl.providerLimits[provider],
		CircuitState: circuitBreaker.GetState().String(),
		FailureCount: circuitBreaker.GetFailureCount(),
	}
}

// ProviderStatus holds status information for a provider
type ProviderStatus struct {
	Provider     string `json:"provider"`
	Available    bool   `json:"available"`
	RateLimit    int    `json:"rate_limit_rpm"`
	CircuitState string `json:"circuit_state"`
	FailureCount int    `json:"failure_count"`
}

// GetAllProviderStatuses returns status for all configured providers
func (prl *ProviderRateLimiter) GetAllProviderStatuses() []ProviderStatus {
	prl.mu.RLock()
	defer prl.mu.RUnlock()

	var statuses []ProviderStatus
	for provider, cb := range prl.circuitBreakers {
		statuses = append(statuses, ProviderStatus{
			Provider:     provider,
			Available:    cb.CanExecute(),
			RateLimit:    prl.providerLimits[provider],
			CircuitState: cb.GetState().String(),
			FailureCount: cb.GetFailureCount(),
		})
	}

	return statuses
}

// getRateLimiter returns the rate limiter for a provider (thread-safe)
func (prl *ProviderRateLimiter) getRateLimiter(provider string) *ratelimit.RateLimiter {
	prl.mu.RLock()
	defer prl.mu.RUnlock()
	return prl.rateLimiters[provider]
}

// getCircuitBreaker returns the circuit breaker for a provider (thread-safe)
func (prl *ProviderRateLimiter) getCircuitBreaker(provider string) *CircuitBreaker {
	prl.mu.RLock()
	defer prl.mu.RUnlock()
	return prl.circuitBreakers[provider]
}

// transitionToHalfOpen transitions a circuit breaker from open to half-open state
func (prl *ProviderRateLimiter) transitionToHalfOpen(provider string) {
	prl.mu.Lock()
	defer prl.mu.Unlock()

	if cb, exists := prl.circuitBreakers[provider]; exists {
		cb.mu.Lock()
		if cb.state == CircuitOpen && time.Now().After(cb.nextRetryTime) {
			cb.state = CircuitHalfOpen
		}
		cb.mu.Unlock()
	}
}

// RetryWithBackoff implements exponential backoff with jitter for retrying failed operations
func RetryWithBackoff(ctx context.Context, operation func() error, maxAttempts int) error {
	var lastErr error

	for attempt := 0; attempt < maxAttempts; attempt++ {
		// Try the operation
		err := operation()
		if err == nil {
			return nil // Success
		}

		lastErr = err

		// Don't wait after the last attempt
		if attempt == maxAttempts-1 {
			break
		}

		// Calculate exponential backoff delay with jitter
		delay := calculateBackoffDelay(attempt)

		// Wait for the calculated delay or until context is cancelled
		select {
		case <-time.After(delay):
			// Continue to next attempt
		case <-ctx.Done():
			return fmt.Errorf("retry cancelled: %w", ctx.Err())
		}
	}

	return fmt.Errorf("operation failed after %d attempts: %w", maxAttempts, lastErr)
}

// calculateBackoffDelay calculates the delay for exponential backoff with jitter
func calculateBackoffDelay(attempt int) time.Duration {
	// Exponential backoff: delay = base * 2^attempt
	delay := BaseRetryDelay * time.Duration(math.Pow(2, float64(attempt)))

	// Cap the delay at maximum
	if delay > MaxRetryDelay {
		delay = MaxRetryDelay
	}

	// Add jitter: ±10% random variation
	jitter := time.Duration(float64(delay) * JitterFactor * (2*rand.Float64() - 1))
	delay += jitter

	// Ensure delay is never negative
	if delay < 0 {
		delay = BaseRetryDelay
	}

	return delay
}

// GetProviderRateLimit returns the configured rate limit for a provider
func (prl *ProviderRateLimiter) GetProviderRateLimit(provider string) int {
	prl.mu.RLock()
	defer prl.mu.RUnlock()
	return prl.providerLimits[provider]
}
