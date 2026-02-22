// Package main provides the command-line interface for the thinktank tool
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"testing"

	"github.com/misty-step/thinktank/internal/config"
	"github.com/misty-step/thinktank/internal/logutil"
	"github.com/misty-step/thinktank/internal/models"
)

// stringSliceFlag is a slice of strings that implements flag.Value interface
// to handle repeatable flags for multiple values
type stringSliceFlag []string

// String returns a comma-separated string representation of the flag values
// This method is required by the flag.Value interface
func (s *stringSliceFlag) String() string {
	return strings.Join(*s, ",")
}

// Set appends the value to the slice of values
// This method is required by the flag.Value interface
func (s *stringSliceFlag) Set(value string) error {
	*s = append(*s, value)
	return nil
}

// Constants referencing the config package defaults
const (
	defaultOutputFile      = config.DefaultOutputFile
	defaultModel           = config.DefaultModel
	apiEndpointEnvVar      = "GEMINI_API_URL"
	defaultFormat          = config.DefaultFormat
	defaultExcludes        = config.DefaultExcludes
	defaultExcludeNames    = config.DefaultExcludeNames
	defaultTimeout         = config.DefaultTimeout
	defaultDirPermissions  = config.DefaultDirPermissions
	defaultFilePermissions = config.DefaultFilePermissions
)

// ValidateInputs checks if the configuration is valid and returns an error if not
// Note: The logger passed to this function should already have context attached
func ValidateInputs(config *config.CliConfig, logger logutil.LoggerInterface) error {
	return ValidateInputsWithEnv(config, logger, os.Getenv)
}

// ValidateInputsWithEnv checks if the configuration is valid and returns an error if not
// This version takes a getenv function for easier testing
// Note: The logger passed to this function should already have context attached
func ValidateInputsWithEnv(config *config.CliConfig, logger logutil.LoggerInterface, getenv func(string) string) error {
	// Validate flag combinations
	if config.Quiet && config.Verbose {
		logger.Error("Cannot use --quiet and --verbose flags together.")
		return fmt.Errorf("conflicting flags: --quiet and --verbose are mutually exclusive")
	}

	// Check for instructions file
	if config.InstructionsFile == "" && !config.DryRun {
		logger.Error("The required --instructions flag is missing.")
		return fmt.Errorf("missing required --instructions flag")
	}

	// Check for input paths
	if len(config.Paths) == 0 {
		logger.Error("At least one file or directory path must be provided as an argument.")
		return fmt.Errorf("no paths specified")
	}

	// Check for API key - all models now use OpenRouter exclusively
	needsAPIKey := false

	// Use models package for model validation
	for _, model := range config.ModelNames {
		provider, err := models.GetProviderForModel(model)
		if err != nil {
			logger.Debug("Model %s not found in models package: %v", model, err)
			// Return validation error for unknown models
			return fmt.Errorf("unknown model: %s", model)
		}

		// All models except test models require OpenRouter API key
		switch provider {
		case "openrouter":
			needsAPIKey = true
		case "test":
			// Test provider doesn't require API keys
			logger.Debug("Test model %s doesn't require API key", model)
		default:
			// Obsolete providers - provide helpful migration message
			logger.Error("Provider '%s' for model '%s' is no longer supported. All models now use OpenRouter.", provider, model)
			return fmt.Errorf("obsolete provider '%s' - all models now use OpenRouter. Set OPENROUTER_API_KEY environment variable", provider)
		}
	}

	// API key validation - single OpenRouter key for all models
	if needsAPIKey {
		openRouterKey := getenv("OPENROUTER_API_KEY")
		if openRouterKey == "" {
			logger.Error("OPENROUTER_API_KEY environment variable not set.")
			return fmt.Errorf("OpenRouter API key not set - get your key at https://openrouter.ai/keys")
		}
	}

	// Check for model names
	if len(config.ModelNames) == 0 && !config.DryRun {
		logger.Error("At least one model must be specified with --model flag.")
		return fmt.Errorf("no models specified")
	}

	// Validate synthesis model if provided
	if config.SynthesisModel != "" {
		logger.Debug("Validating synthesis model: %s", config.SynthesisModel)

		// Check if synthesis model exists in models package
		if !models.IsModelSupported(config.SynthesisModel) {
			logger.Error("Synthesis model '%s' not found in supported models", config.SynthesisModel)
			return fmt.Errorf("invalid synthesis model: '%s' not found or not supported", config.SynthesisModel)
		}
		logger.Debug("Synthesis model '%s' successfully validated", config.SynthesisModel)
	}

	return nil
}

// ParseFlags handles command line argument parsing and returns the configuration
func ParseFlags() (*config.CliConfig, error) {
	return ParseFlagsWithEnv(flag.CommandLine, os.Args[1:], os.Getenv)
}

// ParseFlagsWithEnv handles command-line flag parsing with custom flag set and environment lookup
// This improves testability by allowing tests to provide mock flag sets and environment functions
func ParseFlagsWithEnv(flagSet *flag.FlagSet, args []string, getenv func(string) string) (*config.CliConfig, error) {
	cfg := config.NewDefaultCliConfig()

	// Define flags
	instructionsFileFlag := flagSet.String("instructions", "", "Path to a file containing the static instructions for the LLM.")
	outputDirFlag := flagSet.String("output-dir", "", "Directory path to store generated plans (one per model).")
	synthesisModelFlag := flagSet.String("synthesis-model", "", "Optional: Model to use for synthesizing results from multiple models.")
	verboseFlag := flagSet.Bool("verbose", false, "Enable verbose logging output (shorthand for --log-level=debug).")
	logLevelFlag := flagSet.String("log-level", "info", "Set logging level (debug, info, warn, error).")
	quietFlag := flagSet.Bool("quiet", false, "Suppress console output (errors only).")
	jsonLogsFlag := flagSet.Bool("json-logs", false, "Show JSON logs on stderr (preserves old behavior).")
	noProgressFlag := flagSet.Bool("no-progress", false, "Disable progress indicators (show only start/complete).")
	includeFlag := flagSet.String("include", "", "Comma-separated list of file extensions to include (e.g., .go,.md)")
	excludeFlag := flagSet.String("exclude", defaultExcludes, "Comma-separated list of file extensions to exclude.")
	excludeNamesFlag := flagSet.String("exclude-names", defaultExcludeNames, "Comma-separated list of file/dir names to exclude.")
	formatFlag := flagSet.String("format", defaultFormat, "Format string for each file. Use {path} and {content}.")
	dryRunFlag := flagSet.Bool("dry-run", false, "Show files that would be included and token count, but don't call the API.")
	// confirm-tokens flag removed as part of T032E - token management refactoring
	auditLogFileFlag := flagSet.String("audit-log-file", "", "Path to write structured audit logs (JSON Lines). Disabled if empty.")
	partialSuccessOkFlag := flagSet.Bool("partial-success-ok", false, "Return exit code 0 if any model succeeds and a synthesis file is generated, even if some models fail.")

	// Rate limiting flags
	maxConcurrentFlag := flagSet.Int("max-concurrent", 5, // Use hardcoded default for backward compatibility with tests
		"Maximum number of concurrent API requests (0 = no limit)")
	rateLimitRPMFlag := flagSet.Int("rate-limit", 60, // Use hardcoded default for backward compatibility with tests
		"Maximum requests per minute (RPM) per model (0 = no limit)")

	// Timeout flag
	timeoutFlag := flagSet.Duration("timeout", defaultTimeout,
		"Global timeout for the entire operation (e.g., 60s, 2m, 1h)")

	// Permission flags
	dirPermFlag := flagSet.String("dir-permissions", fmt.Sprintf("%#o", defaultDirPermissions),
		"Directory creation permissions (octal, e.g., 0750)")
	filePermFlag := flagSet.String("file-permissions", fmt.Sprintf("%#o", defaultFilePermissions),
		"File creation permissions (octal, e.g., 0640)")

	// Define the model flag using our custom stringSliceFlag type to support multiple values
	modelFlag := &stringSliceFlag{}
	flagSet.Var(modelFlag, "model", fmt.Sprintf("Model to use for generation (repeatable). All models use OpenRouter (e.g., %s, gpt-5.2, o3). Default: %s", defaultModel, defaultModel))

	// Set custom usage message
	flagSet.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: %s --instructions <file> [options] <path1> [path2...]\n\n", os.Args[0])

		fmt.Fprintf(os.Stderr, "Arguments:\n")
		fmt.Fprintf(os.Stderr, "  <path1> [path2...]   One or more file or directory paths for project context.\n\n")

		fmt.Fprintf(os.Stderr, "Example Commands:\n")
		fmt.Fprintf(os.Stderr, "  %s --instructions instructions.txt ./src                        Generate plan using default model\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s --instructions instructions.txt --output-dir custom-dir ./       Generate plans in custom directory\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s --instructions instructions.txt --model model1 --model model2 ./  Generate plans for multiple models\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s --instructions instructions.txt --synthesis-model model3 ./       Synthesize outputs from multiple models\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s --instructions instructions.txt --timeout 5m ./                  Run with 5-minute timeout\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s --dry-run ./                                                     Show files without generating plan\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s --instructions instructions.txt --partial-success-ok ./          Return success if any model succeeds (tolerant mode)\n\n", os.Args[0])

		fmt.Fprintf(os.Stderr, "Options:\n")
		flagSet.PrintDefaults()

		fmt.Fprintf(os.Stderr, "\nEnvironment Variables:\n")
		fmt.Fprintf(os.Stderr, "  OPENROUTER_API_KEY: Required for all models. Your OpenRouter API key.\n")
		fmt.Fprintf(os.Stderr, "                      Get your key at: https://openrouter.ai/keys\n")
	}

	// Parse the flags
	if err := flagSet.Parse(args); err != nil {
		return nil, fmt.Errorf("error parsing flags: %w", err)
	}

	// Store flag values in configuration
	cfg.InstructionsFile = *instructionsFileFlag

	// Set output directory
	cfg.OutputDir = *outputDirFlag

	// Set synthesis model
	cfg.SynthesisModel = *synthesisModelFlag

	cfg.AuditLogFile = *auditLogFileFlag
	cfg.Verbose = *verboseFlag
	cfg.Quiet = *quietFlag
	cfg.JsonLogs = *jsonLogsFlag
	cfg.NoProgress = *noProgressFlag
	cfg.Include = *includeFlag
	cfg.Exclude = *excludeFlag
	cfg.ExcludeNames = *excludeNamesFlag
	cfg.Format = *formatFlag
	cfg.DryRun = *dryRunFlag
	cfg.PartialSuccessOk = *partialSuccessOkFlag
	// ConfirmTokens field assignment removed as part of T032E - token management refactoring
	cfg.Paths = flagSet.Args()

	// Store rate limiting configuration
	cfg.MaxConcurrentRequests = *maxConcurrentFlag
	cfg.RateLimitRequestsPerMinute = *rateLimitRPMFlag

	// Store timeout configuration
	cfg.Timeout = *timeoutFlag

	// Parse and store permissions
	if dirPerm, err := parseOctalPermission(*dirPermFlag); err == nil {
		cfg.DirPermissions = dirPerm
	} else {
		return nil, fmt.Errorf("invalid directory permission format: %w", err)
	}

	if filePerm, err := parseOctalPermission(*filePermFlag); err == nil {
		cfg.FilePermissions = filePerm
	} else {
		return nil, fmt.Errorf("invalid file permission format: %w", err)
	}

	// Set model names from the flag, defaulting to a single default model if none provided
	if len(*modelFlag) > 0 {
		cfg.ModelNames = *modelFlag
	} else {
		// If no models were specified on the command line, use the default model
		cfg.ModelNames = []string{defaultModel}
	}

	// Determine initial log level from flag
	parsedLogLevel := logutil.InfoLevel // Default
	if *logLevelFlag != "info" {
		ll, err := logutil.ParseLogLevel(*logLevelFlag)
		if err == nil {
			parsedLogLevel = ll
		}
	}
	cfg.LogLevel = parsedLogLevel

	// Apply verbose override *after* parsing the specific level
	if cfg.Verbose {
		cfg.LogLevel = logutil.DebugLevel
	}
	// Line removed per T105: No longer hardcoding Gemini API key
	// The API key should be determined by the provider-specific logic in InitLLMClient
	cfg.APIEndpoint = getenv(apiEndpointEnvVar)

	// ParseFlagsWithEnv no longer does logical validation (just parsing errors)
	// Validation is now exclusively handled by ValidateInputs
	return cfg, nil
}

// parseOctalPermission converts a string representation of an octal permission
// to an os.FileMode
func parseOctalPermission(permStr string) (os.FileMode, error) {
	// Parse the octal permission string
	n, err := strconv.ParseUint(strings.TrimPrefix(permStr, "0"), 8, 32)
	if err != nil {
		return 0, err
	}
	return os.FileMode(n), nil
}

// setupLoggingCustomImpl is the implementation of SetupLoggingCustom
func setupLoggingCustomImpl(config *config.CliConfig, _ *flag.Flag, output io.Writer) logutil.LoggerInterface {
	// When testing, use the old logger to maintain compatibility with existing tests
	if testing.Testing() {
		// Make sure verbose flag is properly handled for tests
		if config.Verbose {
			config.LogLevel = logutil.DebugLevel
		}
		return logutil.NewLogger(config.LogLevel, output, "[thinktank] ")
	}
	// Apply verbose override if set
	if config.Verbose {
		config.LogLevel = logutil.DebugLevel
	}

	// Create a structured JSON logger using slog
	slogLevel := logutil.ConvertLogLevelToSlog(config.LogLevel)

	// Split logging streams if configured
	if config.SplitLogs {
		// This will route INFO/DEBUG to STDOUT and WARN/ERROR to STDERR
		// But since we're just using output here, we'll use the standard slog logger
		// The caller should provide the appropriate output (os.Stdout or os.Stderr)
		logger := logutil.NewSlogLoggerFromLogLevel(output, config.LogLevel)
		return logger
	}

	// Standard structured logger using slog
	logger := logutil.NewSlogLogger(output, slogLevel)

	// Note: The WithContext call should be done at the entry point after context creation
	// This function just creates the base logger
	return logger
}

// SetupLoggingCustom is a variable holding the implementation for easier testing
var SetupLoggingCustom = setupLoggingCustomImpl

// SetupLogging initializes the logger based on configuration
func SetupLogging(config *config.CliConfig) logutil.LoggerInterface {
	return SetupLoggingCustom(config, flag.Lookup("log-level"), os.Stderr)
}
