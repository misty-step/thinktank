// Package config handles loading and managing application configuration.
// It defines a canonical set of configuration parameters used throughout
// the application, consolidating configuration from CLI flags, environment
// variables, and default values. This centralized approach ensures
// consistent configuration handling and reduces duplication.
package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/misty-step/thinktank/internal/logutil"
)

// Configuration constants
const (
	// Default values
	DefaultOutputFile      = "PLAN.md"
	DefaultModel           = "gemini-3-flash"
	OpenRouterAPIKeyEnvVar = "OPENROUTER_API_KEY"
	DefaultFormat          = "<{path}>\n```\n{content}\n```\n</{path}>\n\n"

	// DefaultMaxConcurrentRequests limits parallel API calls to balance throughput
	// against memory usage and rate limits. The value of 5 is a conservative
	// sweet spot for most provider limits: higher values risk rate limit errors,
	// while lower values leave throughput on the table.
	DefaultMaxConcurrentRequests = 5
	// DefaultRateLimitRequestsPerMinute caps requests per minute per model. The
	// default of 60 matches the OpenRouter free tier limit and is conservative
	// across API tiers. Users with higher tiers can raise this via --rate-limit.
	DefaultRateLimitRequestsPerMinute = 60

	// DefaultTimeout bounds the entire operation. Large codebases can exceed five
	// minutes, and slower deep-thinking models add more latency. Ten minutes
	// covers network delays, rate limit waiting, and processing time.
	DefaultTimeout = 10 * time.Minute

	// DefaultDirPermissions sets created output directories to 0750. This is more
	// restrictive than 0755: owner gets full access, group gets read/execute, and
	// others get none. It helps avoid accidental exposure of sensitive analysis.
	DefaultDirPermissions = 0750
	// DefaultFilePermissions sets created files to 0640. This is more restrictive
	// than 0644: owner can read/write, group can read, and others get none.
	// Output files may include sensitive code snippets or analysis.
	DefaultFilePermissions = 0640

	// Default excludes for file extensions
	DefaultExcludes = ".exe,.bin,.obj,.o,.a,.lib,.so,.dll,.dylib,.class,.jar,.pyc,.pyo,.pyd," +
		".zip,.tar,.gz,.rar,.7z,.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.odt,.ods,.odp," +
		".jpg,.jpeg,.png,.gif,.bmp,.tiff,.svg,.mp3,.wav,.ogg,.mp4,.avi,.mov,.wmv,.flv," +
		".iso,.img,.dmg,.db,.sqlite,.log"

	// Default excludes for file and directory names
	DefaultExcludeNames = ".git,.hg,.svn,node_modules,bower_components,vendor,target,dist,build," +
		"out,tmp,coverage,__pycache__,*.pyc,*.pyo,.DS_Store,~$*,desktop.ini,Thumbs.db," +
		"package-lock.json,yarn.lock,go.sum,go.work"
)

// ExcludeConfig defines file exclusion configuration
type ExcludeConfig struct {
	// File extensions to exclude
	Extensions string
	// File and directory names to exclude
	Names string
}

// AppConfig holds essential configuration settings with defaults
type AppConfig struct {
	// Core settings with defaults
	OutputFile string
	ModelName  string
	Format     string

	// File handling settings
	Include string
	// ConfirmTokens field removed as part of T032E

	// Logging and display settings
	Verbose  bool
	LogLevel logutil.LogLevel

	// Exclude settings (hierarchical)
	Excludes ExcludeConfig
}

// DefaultConfig returns a new AppConfig instance with default values
func DefaultConfig() *AppConfig {
	return &AppConfig{
		OutputFile: DefaultOutputFile,
		ModelName:  DefaultModel,
		Format:     DefaultFormat,
		LogLevel:   logutil.InfoLevel,
		// ConfirmTokens removed as part of T032E - token management refactoring
		Excludes: ExcludeConfig{
			Extensions: DefaultExcludes,
			Names:      DefaultExcludeNames,
		},
	}
}

// CliConfig holds the parsed command-line options for the application.
// It serves as the canonical configuration structure used throughout the
// application, combining user inputs from CLI flags, environment variables,
// and default values. This struct is passed to components that need
// configuration parameters rather than having them parse flags directly.
//
// SIMPLIFICATION STATUS (Phase 7 - Code Cleanup):
// Many fields in this struct are now handled by smart defaults:
// - Rate limiting fields: Auto-detected based on provider capabilities
// - API configuration: Auto-detected from environment variables
// - File permissions: Use OS defaults with intelligent override
// - Complex validation: Simplified through parser router and adapters
// The simplified interface (SimplifiedConfig) reduces user-facing complexity
// while this comprehensive struct maintains backward compatibility.
type CliConfig struct {
	// Instructions configuration
	InstructionsFile string

	// Output configuration
	OutputDir    string
	AuditLogFile string // Path to write structured audit logs (JSON Lines)
	Format       string

	// Context gathering options
	Paths        []string
	Include      string
	Exclude      string
	ExcludeNames string
	DryRun       bool
	Verbose      bool

	// API configuration
	APIKey      string
	APIEndpoint string
	ModelNames  []string
	// SynthesisModel specifies the model to use for combining (synthesizing) outputs from multiple models.
	// When specified, all individual model outputs will be sent to this model along with original instructions,
	// and the synthesis model will generate a consolidated result combining insights from all models.
	// The synthesized output will be saved with the format `<synthesis-model-name>-synthesis.md`.
	SynthesisModel string

	// Token management field removed as part of T032E

	// Logging
	LogLevel   logutil.LogLevel
	SplitLogs  bool // Whether to split logs by level (INFO/DEBUG to stdout, WARN/ERROR to stderr)
	Quiet      bool // Suppress console output (errors only)
	JsonLogs   bool // Show JSON logs on stderr (preserves old behavior)
	NoProgress bool // Disable progress indicators (show only start/complete)

	// Rate limiting configuration
	MaxConcurrentRequests      int // Maximum number of concurrent API requests (0 = no limit)
	RateLimitRequestsPerMinute int // Maximum requests per minute per model (0 = no limit)

	// Provider-specific rate limiting (overrides global rate limit for specific providers)
	OpenAIRateLimit     int // OpenAI-specific rate limit (0 = use provider default)
	GeminiRateLimit     int // Gemini-specific rate limit (0 = use provider default)
	OpenRouterRateLimit int // OpenRouter-specific rate limit (0 = use provider default)

	// Timeout configuration
	Timeout time.Duration // Global timeout for the entire operation

	// Permission configuration
	DirPermissions  os.FileMode // Directory permissions
	FilePermissions os.FileMode // File permissions

	// Error handling configuration
	// PartialSuccessOk determines whether to consider a run successful when some, but not all,
	// models succeed. When true, the application exits with code 0 if at least one model succeeds
	// and a synthesis file was generated (if synthesis is enabled). When false (default), any model
	// failure results in a non-zero exit code.
	PartialSuccessOk bool

	// Warning configuration
	// SuppressDeprecationWarnings suppresses deprecation warnings in CI/automation environments
	// where they are not actionable. When true, warnings are logged to debug but not shown to stderr.
	// Can be set via --no-deprecation-warnings flag or THINKTANK_SUPPRESS_DEPRECATION_WARNINGS env var.
	SuppressDeprecationWarnings bool

	// Token safety margin percentage (0-50%) - percentage of context window reserved for output
	TokenSafetyMargin uint8
}

// NewDefaultCliConfig returns a CliConfig with default values.
// This is used as a starting point before parsing CLI flags, ensuring
// that all fields have sensible defaults even if not explicitly set
// by the user.
func NewDefaultCliConfig() *CliConfig {
	return &CliConfig{
		Format:                      DefaultFormat,
		Exclude:                     DefaultExcludes,
		ExcludeNames:                DefaultExcludeNames,
		ModelNames:                  []string{DefaultModel},
		LogLevel:                    logutil.InfoLevel,
		MaxConcurrentRequests:       DefaultMaxConcurrentRequests,
		RateLimitRequestsPerMinute:  DefaultRateLimitRequestsPerMinute,
		Timeout:                     DefaultTimeout,
		DirPermissions:              DefaultDirPermissions,
		FilePermissions:             DefaultFilePermissions,
		PartialSuccessOk:            false, // Default to strict error handling
		SuppressDeprecationWarnings: false, // Default to showing warnings
		// Provider-specific rate limits default to 0 (use provider defaults)
		OpenAIRateLimit:     0,
		GeminiRateLimit:     0,
		OpenRouterRateLimit: 0,
		// TokenSafetyMargin reserves part of the context window for model output.
		// A 10% margin reduces truncation risk when responses are long, while
		// keeping most tokens available for input. Users can tune this via the
		// --token-safety-margin flag when they need tighter or looser margins.
		TokenSafetyMargin: 10,
	}
}

// GetProviderRateLimit returns the effective rate limit for a given provider.
// It checks provider-specific overrides first, then falls back to global rate limit,
// then finally to provider defaults if both are zero.
func (c *CliConfig) GetProviderRateLimit(provider string) int {
	// Check provider-specific override first
	switch provider {
	case "openrouter":
		if c.OpenRouterRateLimit > 0 {
			return c.OpenRouterRateLimit
		}
	case "test":
		// Test provider always uses global settings
	default:
		// Obsolete providers (openai, gemini) - check legacy overrides for backward compatibility
		if provider == "openai" && c.OpenAIRateLimit > 0 {
			return c.OpenAIRateLimit
		}
		if provider == "gemini" && c.GeminiRateLimit > 0 {
			return c.GeminiRateLimit
		}
	}

	// Fall back to global rate limit if set
	if c.RateLimitRequestsPerMinute > 0 {
		return c.RateLimitRequestsPerMinute
	}

	// Final fallback: use provider default (this will be handled by models package)
	return 0
}

// ValidateConfig checks if the configuration is valid and returns an error if not.
// It performs validation beyond simple type-checking, such as verifying that
// required fields are present, paths exist, and values are within acceptable ranges.
// This helps catch configuration errors early before they cause runtime failures.
func ValidateConfig(config *CliConfig, logger logutil.LoggerInterface) error {
	return ValidateConfigWithEnv(config, logger, os.Getenv)
}

// ValidateConfigWithEnv checks if the configuration is valid and returns an error if not.
// This version takes a getenv function for easier testing by allowing environment variables
// to be mocked.
func ValidateConfigWithEnv(config *CliConfig, logger logutil.LoggerInterface, getenv func(string) string) error {
	// Handle nil config
	if config == nil {
		if logger != nil {
			logger.Error("Configuration is nil")
		}
		return fmt.Errorf("nil config provided")
	}

	// Define a safe logger function that won't panic if logger is nil
	logError := func(format string, args ...interface{}) {
		if logger != nil {
			logger.Error(format, args...)
		}
	}

	// Check for valid paths (always required)
	validPaths := false
	if len(config.Paths) > 0 {
		for _, path := range config.Paths {
			if len(strings.TrimSpace(path)) > 0 {
				validPaths = true
				break
			}
		}
	}

	if !validPaths {
		logError("At least one file or directory path must be provided as an argument.")
		return fmt.Errorf("no paths specified")
	}

	// Check for instructions file (required unless in dry run mode)
	if config.InstructionsFile == "" && !config.DryRun {
		logError("The required --instructions flag is missing.")
		return fmt.Errorf("missing required --instructions flag")
	}

	// All models now use OpenRouter after consolidation, except test models
	modelNeedsOpenRouterKey := false

	// Check if any non-test model is being used
	for _, model := range config.ModelNames {
		if !strings.Contains(strings.ToLower(model), "test") {
			modelNeedsOpenRouterKey = true
			break
		}
	}

	// Also check synthesis model if specified
	if config.SynthesisModel != "" && !strings.Contains(strings.ToLower(config.SynthesisModel), "test") {
		modelNeedsOpenRouterKey = true
	}

	// API key validation - only check for OpenRouter key (skip in dry run mode)
	if modelNeedsOpenRouterKey && !config.DryRun {
		openRouterKey := getenv(OpenRouterAPIKeyEnvVar)
		if openRouterKey == "" {
			logError("%s environment variable not set.", OpenRouterAPIKeyEnvVar)
			return fmt.Errorf("API key not set: please set %s", OpenRouterAPIKeyEnvVar)
		}
	}

	// Check for model names (required unless in dry run mode)
	if len(config.ModelNames) == 0 && !config.DryRun {
		logError("At least one model must be specified with --model flag.")
		return fmt.Errorf("no models specified")
	}

	return nil
}
