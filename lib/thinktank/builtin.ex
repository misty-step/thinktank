defmodule Thinktank.Builtin do
  @moduledoc false

  def raw_config do
    %{
      "version" => 1,
      "providers" => %{
        "openrouter" => %{
          "adapter" => "openrouter",
          "credential_env" => "THINKTANK_OPENROUTER_API_KEY",
          "defaults" => %{"fallback_env" => "OPENROUTER_API_KEY"}
        }
      },
      "agents" => %{
        "trace" =>
          reviewer_agent("trace", "x-ai/grok-4.1-fast", trace_prompt(), thinking_level: "medium"),
        "guard" =>
          reviewer_agent(
            "guard",
            "google/gemini-3-flash-preview",
            guard_prompt(),
            thinking_level: "low"
          ),
        "proof" =>
          reviewer_agent(
            "proof",
            "mistralai/mistral-large-2512",
            proof_prompt(),
            thinking_level: "medium"
          ),
        "atlas" =>
          reviewer_agent(
            "atlas",
            "anthropic/claude-sonnet-4.6",
            atlas_prompt(),
            thinking_level: "medium"
          ),
        "fuse" =>
          reviewer_agent("fuse", "openai/gpt-5.4", fuse_prompt(), thinking_level: "medium"),
        "craft" =>
          reviewer_agent(
            "craft",
            "deepseek/deepseek-v3.2",
            craft_prompt(),
            thinking_level: "medium"
          )
      },
      "workflows" => %{
        "research/default" => %{
          "description" =>
            "Multi-perspective research workflow with routing, parallel fanout, and synthesis.",
          "input_schema" => %{"required" => ["input_text"]},
          "default_mode" => "quick",
          "execution_mode" => "flexible",
          "stages" => [
            %{"name" => "prepare", "type" => "prepare", "kind" => "research_input"},
            %{
              "name" => "route",
              "type" => "route",
              "kind" => "research_router",
              "count" => 4
            },
            %{
              "name" => "fanout",
              "type" => "fanout",
              "kind" => "agents",
              "concurrency" => 4
            },
            %{
              "name" => "aggregate",
              "type" => "aggregate",
              "kind" => "research_synthesis",
              "when" => "should_synthesize"
            },
            %{"name" => "emit", "type" => "emit", "kind" => "artifacts"}
          ]
        },
        "review/cerberus" => %{
          "description" =>
            "Diff-aware multi-agent code review with reviewer routing and verdict aggregation.",
          "input_schema" => %{},
          "default_mode" => "deep",
          "execution_mode" => "deep",
          "stages" => [
            %{"name" => "prepare", "type" => "prepare", "kind" => "review_diff"},
            %{
              "name" => "route",
              "type" => "route",
              "kind" => "cerberus_review",
              "panel_size" => 4,
              "always_include" => ["trace"],
              "include_if_code_changed" => ["guard"],
              "fallback_panel" => ["atlas", "proof", "fuse", "craft"]
            },
            %{
              "name" => "fanout",
              "type" => "fanout",
              "kind" => "agents",
              "concurrency" => 4
            },
            %{
              "name" => "aggregate",
              "type" => "aggregate",
              "kind" => "cerberus_verdict"
            },
            %{"name" => "emit", "type" => "emit", "kind" => "artifacts"}
          ]
        }
      }
    }
  end

  defp reviewer_agent(name, model, system_prompt, opts) do
    %{
      "provider" => "openrouter",
      "model" => model,
      "system_prompt" => system_prompt,
      "prompt" => review_prompt_template(),
      "tool_profile" => "review",
      "output_format" => "structured_verdict",
      "thinking_level" => Keyword.get(opts, :thinking_level, "medium"),
      "retries" => Keyword.get(opts, :retries, 0),
      "timeout_ms" => Keyword.get(opts, :timeout_ms, :timer.minutes(6)),
      "metadata" => %{"perspective" => name}
    }
  end

  defp review_prompt_template do
    """
    {{input_text}}

    {{review_bundle}}

    This workflow is agentic. Use your tools to inspect the repository, the branch diff,
    and any nearby code or tests you need before deciding.
    Start with the diff file and changed paths, then inspect only the changed files and the
    nearest supporting modules or tests needed to verify a claim. Do not do broad repository
    sweeps when the diff and adjacent code are enough.
    Deep review runs with file-system tools, not an unrestricted shell. Read the diff file
    and changed files directly instead of assuming shell access.

    Review only issues you can ground in the actual code, diff, or repository context.
    If there is not enough evidence for a claim, do not report it.
    Respect the stated v1 scope in this change. The constrained built-in stage graph and
    first-party provider wiring are deliberate design choices for now, not defects by themselves.
    Fixed v1 routing heuristics such as the built-in diff-size buckets are also deliberate unless
    they contradict a documented contract or cause a concrete bug here.
    Fail-closed review behavior when no valid reviewer verdicts are produced is deliberate.
    Separate repo trust controls for YAML config versus agent home directories are deliberate,
    because agent homes contain executable and stateful resources.
    Ignore untouched legacy modules unless they are exercised by the current workflow path or
    directly implicated by the diff.
    Do not report roadmap requests, alternative abstractions, or generic missing-test suggestions
    unless they reveal a concrete bug, regression, security problem, or violated contract here.

    Return a short markdown review followed by exactly one fenced ```json block.
    The JSON must be valid and must not contain comments or unescaped quotes.
    If you find no substantive issues, return verdict PASS with findings [].

    The JSON object must include:
    - reviewer
    - perspective
    - verdict (PASS, WARN, FAIL, or SKIP)
    - confidence (0.0 to 1.0)
    - summary
    - findings: array of objects with severity, category, title, description, suggestion, file, line
    - stats: object with files_reviewed, files_with_issues, critical, major, minor, info

    Focus only on substantive issues grounded in the provided diff and repository context.
    """
  end

  defp trace_prompt do
    """
    You are trace, a correctness reviewer. Hunt for behavioral regressions, edge cases,
    broken control flow, and incorrect assumptions in the change. Ignore style-only nits.
    """
  end

  defp guard_prompt do
    """
    You are guard, a security reviewer. Look for auth flaws, injection risk, unsafe defaults,
    permission mistakes, secret exposure, and trust-boundary violations. Separate argv-based
    subprocess calls with validated inputs are not shell injection on their own; report only
    exploitable argument-boundary bugs.
    """
  end

  defp proof_prompt do
    """
    You are proof, a testing reviewer. Look for concrete regression gaps, brittle tests,
    and unverified behavior that could plausibly fail in this change. Do not ask for
    generic extra coverage without identifying a real risk.
    """
  end

  defp atlas_prompt do
    """
    You are atlas, an architecture reviewer. Focus on boundaries, coupling, module depth,
    and whether the change makes the design materially harder to evolve within the stated
    v1 constraints. Do not report deliberate fixed stage kinds or first-party provider seams
    as defects unless they break the documented contract in this change.
    """
  end

  defp fuse_prompt do
    """
    You are fuse, a resilience reviewer. Focus on failure handling, retries, degradation,
    observability gaps, and whether unhappy paths are safe.
    """
  end

  defp craft_prompt do
    """
    You are craft, a maintainability reviewer. Focus on readability, accidental complexity,
    naming, duplication, and whether the next engineer will be able to work safely here.
    """
  end
end
