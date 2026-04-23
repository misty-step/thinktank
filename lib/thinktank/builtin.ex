defmodule Thinktank.Builtin do
  @moduledoc false

  alias Thinktank.Prompts.{Research, Review, Synthesis}

  @agent_tools ["bash", "read", "grep", "find", "ls"]
  @summary_tools ["read", "ls"]

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
      "agents" => research_agents() |> Map.merge(review_agents()) |> Map.merge(synth_agents()),
      "benches" => %{
        "research/quick" => %{
          "kind" => "research",
          "description" =>
            "Launch a fast repo-aware research bench without a synthesizer " <>
              "for quick local grounding.",
          "agents" => ["systems", "verification"],
          "concurrency" => 2
        },
        "research/default" => %{
          "kind" => "research",
          "description" =>
            "Launch a fixed research bench of Pi agents and optionally synthesize their findings.",
          "structured_findings" => true,
          "agents" => ["systems", "verification", "ml", "dx"],
          "synthesizer" => "research-synth",
          "concurrency" => 4
        },
        "review/default" => %{
          "kind" => "review",
          "description" =>
            "Launch the review bench: marshal plans, selects reviewers " <>
              "from the full roster, then synthesizes.",
          "agents" => [
            "trace",
            "guard",
            "atlas",
            "proof",
            "vector",
            "pulse",
            "scout",
            "forge",
            "orbit",
            "sentry"
          ],
          "planner" => "marshal",
          "synthesizer" => "review-synth",
          "concurrency" => 10,
          "default_task" => "Review the current change and report only real issues with evidence."
        }
      }
    }
  end

  defp research_agents do
    %{
      "systems" =>
        agent(
          "systems",
          "anthropic/claude-sonnet-4.6",
          Research.systems(),
          Research.task(),
          @agent_tools
        ),
      "verification" =>
        agent(
          "verification",
          "arcee-ai/trinity-large-thinking",
          Research.verification(),
          Research.task(),
          @agent_tools
        ),
      "ml" => agent("ml", "x-ai/grok-4.1-fast", Research.ml(), Research.task(), @agent_tools),
      "dx" =>
        agent(
          "dx",
          "google/gemini-3-flash-preview",
          Research.dx(),
          Research.task(),
          @agent_tools,
          thinking_level: "low"
        )
    }
  end

  defp review_agents do
    # Reviewer models MUST advertise `tools` in their OpenRouter
    # supported_parameters. xAI's `*-multi-agent` variants orchestrate their
    # own tool fabric internally and do NOT accept a user-supplied tool
    # schema over OpenRouter, so they 404 against any bench that declares
    # @agent_tools. Keep those variants out of this roster.
    reviewers = [
      {"trace", "x-ai/grok-4.20", Review.trace(), "correctness"},
      {"guard", "x-ai/grok-4.20", Review.guard(), "security"},
      {"atlas", "openai/gpt-5.4-mini", Review.atlas(), "architecture"},
      {"proof", "openai/gpt-5.4-mini", Review.proof(), "tests"},
      {"vector", "z-ai/glm-5.1", Review.vector(), "interfaces"},
      {"pulse", "minimax/minimax-m2.7", Review.pulse(), "runtime-risk"},
      {"scout", "google/gemini-3-flash-preview", Review.scout(), "integration"},
      {"forge", "inception/mercury-2", Review.forge(), "implementation"},
      {"orbit", "moonshotai/kimi-k2.6", Review.orbit(), "compatibility"},
      {"sentry", "xiaomi/mimo-v2-pro", Review.sentry(), "operability"}
    ]

    agents =
      Map.new(reviewers, fn {name, model, system, role} ->
        {name,
         agent(name, model, system, Review.task(), @agent_tools,
           thinking_level: "high",
           retries: 2,
           metadata: %{"review_role" => role}
         )}
      end)

    Map.put(
      agents,
      "marshal",
      agent("marshal", "openai/gpt-5.4", Review.marshal(), Review.plan_task(), @agent_tools,
        thinking_level: "high",
        retries: 2,
        metadata: %{"review_role" => "planner"}
      )
    )
  end

  defp synth_agents do
    %{
      "research-synth" =>
        agent(
          "research-synth",
          "openai/gpt-5.4",
          Synthesis.research_system(),
          Synthesis.research_task(),
          @summary_tools
        ),
      "review-synth" =>
        agent(
          "review-synth",
          "openai/gpt-5.4",
          Synthesis.review_system(),
          Synthesis.review_task(),
          @summary_tools,
          thinking_level: "high",
          retries: 2
        )
    }
  end

  defp agent(name, model, system_prompt, task_prompt, tools, opts \\ []) do
    metadata =
      %{"agent" => name}
      |> Map.merge(Keyword.get(opts, :metadata, %{}))

    %{
      "provider" => "openrouter",
      "model" => model,
      "system_prompt" => system_prompt,
      "task_prompt" => task_prompt,
      "tools" => tools,
      "thinking_level" => Keyword.get(opts, :thinking_level, "medium"),
      "retries" => Keyword.get(opts, :retries, 0),
      "timeout_ms" => Keyword.get(opts, :timeout_ms, :timer.minutes(10)),
      "metadata" => metadata
    }
  end
end
