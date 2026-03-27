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
        "trace" => reviewer_agent("trace", "x-ai/grok-4.1-fast", trace_prompt()),
        "guard" => reviewer_agent("guard", "google/gemini-3-flash-preview", guard_prompt()),
        "proof" => reviewer_agent("proof", "deepseek/deepseek-v3.2", proof_prompt()),
        "atlas" => reviewer_agent("atlas", "openai/gpt-5.4", atlas_prompt()),
        "fuse" => reviewer_agent("fuse", "anthropic/claude-sonnet-4.6", fuse_prompt()),
        "craft" => reviewer_agent("craft", "mistralai/mistral-large-2512", craft_prompt())
      },
      "workflows" => %{
        "research/default" => %{
          "description" => "Multi-perspective research workflow with routing, parallel fanout, and synthesis.",
          "input_schema" => %{"required" => ["input_text"]},
          "default_mode" => "quick",
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
            %{"name" => "aggregate", "type" => "aggregate", "kind" => "research_synthesis"},
            %{"name" => "emit", "type" => "emit", "kind" => "artifacts"}
          ]
        },
        "review/cerberus" => %{
          "description" => "Diff-aware multi-agent code review with reviewer routing and verdict aggregation.",
          "input_schema" => %{},
          "default_mode" => "quick",
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

  defp reviewer_agent(name, model, system_prompt) do
    %{
      "provider" => "openrouter",
      "model" => model,
      "system_prompt" => system_prompt,
      "prompt" => review_prompt_template(),
      "tool_profile" => "review",
      "thinking_level" => "high",
      "retries" => 1,
      "timeout_ms" => :timer.minutes(15),
      "metadata" => %{"perspective" => name}
    }
  end

  defp review_prompt_template do
    """
    {{input_text}}

    {{review_bundle}}

    Review only issues you can ground in the provided diff or nearby repository context.
    If there is not enough evidence for a claim, do not report it.

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
    permission mistakes, secret exposure, and trust-boundary violations.
    """
  end

  defp proof_prompt do
    """
    You are proof, a testing reviewer. Look for missing coverage, brittle tests, regression
    gaps, and places where the change is under-specified or unverified.
    """
  end

  defp atlas_prompt do
    """
    You are atlas, an architecture reviewer. Focus on boundaries, coupling, module depth,
    and whether the change makes the design harder to evolve.
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
