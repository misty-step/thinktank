defmodule Thinktank.Builtin do
  @moduledoc false

  @review_tools ["bash", "read", "grep", "find", "ls"]
  @research_tools ["bash", "read", "grep", "find", "ls"]
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
      "agents" => %{
        "systems" =>
          agent(
            "systems",
            "anthropic/claude-sonnet-4.6",
            systems_prompt(),
            research_task_prompt(),
            @research_tools
          ),
        "verification" =>
          agent(
            "verification",
            "mistralai/mistral-large-2512",
            verification_prompt(),
            research_task_prompt(),
            @research_tools
          ),
        "ml" =>
          agent(
            "ml",
            "x-ai/grok-4.1-fast",
            ml_prompt(),
            research_task_prompt(),
            @research_tools
          ),
        "dx" =>
          agent(
            "dx",
            "google/gemini-3-flash-preview",
            dx_prompt(),
            research_task_prompt(),
            @research_tools,
            thinking_level: "low"
          ),
        "marshal" =>
          agent(
            "marshal",
            "google/gemini-3.1-pro-preview",
            marshal_prompt(),
            review_plan_task_prompt(),
            @review_tools,
            thinking_level: "high",
            metadata: %{"review_role" => "planner"}
          ),
        "trace" =>
          agent(
            "trace",
            "x-ai/grok-4.20-beta",
            trace_prompt(),
            review_task_prompt(),
            @review_tools,
            metadata: %{"review_role" => "correctness"}
          ),
        "guard" =>
          agent(
            "guard",
            "x-ai/grok-4.20-multi-agent-beta",
            guard_prompt(),
            review_task_prompt(),
            @review_tools,
            thinking_level: "low",
            metadata: %{"review_role" => "security"}
          ),
        "atlas" =>
          agent(
            "atlas",
            "anthropic/claude-sonnet-4.6",
            atlas_prompt(),
            review_task_prompt(),
            @review_tools,
            metadata: %{"review_role" => "architecture"}
          ),
        "proof" =>
          agent(
            "proof",
            "openai/gpt-5.4-mini",
            proof_prompt(),
            review_task_prompt(),
            @review_tools,
            metadata: %{"review_role" => "tests"}
          ),
        "vector" =>
          agent(
            "vector",
            "z-ai/glm-5-turbo",
            vector_prompt(),
            review_task_prompt(),
            @review_tools,
            metadata: %{"review_role" => "interfaces"}
          ),
        "pulse" =>
          agent(
            "pulse",
            "minimax/minimax-m2.7",
            pulse_prompt(),
            review_task_prompt(),
            @review_tools,
            metadata: %{"review_role" => "runtime-risk"}
          ),
        "scout" =>
          agent(
            "scout",
            "google/gemini-3-flash-preview",
            scout_prompt(),
            review_task_prompt(),
            @review_tools,
            thinking_level: "low",
            metadata: %{"review_role" => "integration"}
          ),
        "forge" =>
          agent(
            "forge",
            "inception/mercury-2",
            forge_prompt(),
            review_task_prompt(),
            @review_tools,
            metadata: %{"review_role" => "implementation"}
          ),
        "orbit" =>
          agent(
            "orbit",
            "moonshotai/kimi-k2.5",
            orbit_prompt(),
            review_task_prompt(),
            @review_tools,
            metadata: %{"review_role" => "compatibility"}
          ),
        "sentry" =>
          agent(
            "sentry",
            "xiaomi/mimo-v2-pro",
            sentry_prompt(),
            review_task_prompt(),
            @review_tools,
            metadata: %{"review_role" => "operability"}
          ),
        "research-synth" =>
          agent(
            "research-synth",
            "openai/gpt-5.4",
            research_synth_prompt(),
            research_synthesis_task_prompt(),
            @summary_tools
          ),
        "review-synth" =>
          agent(
            "review-synth",
            "openai/gpt-5.4",
            review_synth_prompt(),
            review_synthesis_task_prompt(),
            @summary_tools
          )
      },
      "benches" => %{
        "research/default" => %{
          "kind" => "research",
          "description" =>
            "Launch a fixed research bench of Pi agents and optionally synthesize their findings.",
          "agents" => ["systems", "verification", "ml", "dx"],
          "synthesizer" => "research-synth",
          "concurrency" => 4
        },
        "review/cerberus" => %{
          "kind" => "review",
          "description" =>
            "Launch the default review bench: a planner plus a focused team of specialist reviewers.",
          "agents" => ["trace", "guard", "atlas", "proof", "scout"],
          "planner" => "marshal",
          "synthesizer" => "review-synth",
          "concurrency" => 5,
          "default_task" => "Review the current change and report only real issues with evidence."
        },
        "review/constellation" => %{
          "kind" => "review",
          "description" =>
            "Launch the expanded review roster across model families with a planner and synthesizer.",
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
          "concurrency" => 8,
          "default_task" => "Review the current change and report only real issues with evidence."
        }
      }
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

  defp research_task_prompt do
    """
    {{input_text}}

    Workspace root: {{workspace_root}}
    Focus paths:
    {{paths_hint}}

    Use your tools to inspect the repository, docs, and git state yourself.
    Start from the workspace and any pointed paths. Gather your own context.
    Report concrete findings, tradeoffs, and recommendations. Cite files and commands when useful.
    """
  end

  defp review_task_prompt do
    """
    {{input_text}}

    Workspace root: {{workspace_root}}
    Repo: {{repo}}
    PR: {{pr}}
    Base ref: {{base}}
    Head ref: {{head}}
    Focus paths:
    {{paths_hint}}

    Review role: {{review_role}}
    Assigned brief:
    {{review_brief}}

    Review context:
    {{review_context}}

    Bench plan:
    {{review_plan}}

    You are doing code review. Use bash, git, and file tools to inspect the current repository yourself.
    Start with git status and git diff. If base/head are provided, compare them. If repo/pr are provided,
    use them as orientation, not as a substitute for local inspection. Report only issues you can ground in
    the actual repository state, diff, or nearby code.
    """
  end

  defp review_plan_task_prompt do
    """
    {{input_text}}

    Workspace root: {{workspace_root}}
    Repo: {{repo}}
    PR: {{pr}}
    Base ref: {{base}}
    Head ref: {{head}}
    Focus paths:
    {{paths_hint}}

    Review context:
    {{review_context}}

    Available reviewers:
    {{review_roster}}

    Return JSON only with this shape:
    {
      "summary": "one short paragraph",
      "selected_agents": [
        {"name": "trace", "brief": "what this reviewer should focus on"}
      ],
      "synthesis_brief": "what the synthesizer should prioritize",
      "warnings": ["optional planner caveat"]
    }

    Pick only reviewers that materially add signal for this change. Avoid selecting everyone unless the
    change is genuinely broad. Do not report findings here. This step is only planning and tasking.
    """
  end

  defp research_synthesis_task_prompt do
    """
    Original task:
    {{input_text}}

    Workspace root: {{workspace_root}}
    Focus paths:
    {{paths_hint}}

    Agent outputs:
    {{agent_outputs}}
    """
  end

  defp review_synthesis_task_prompt do
    """
    Original task:
    {{input_text}}

    Workspace root: {{workspace_root}}
    Repo: {{repo}}
    PR: {{pr}}
    Base ref: {{base}}
    Head ref: {{head}}
    Focus paths:
    {{paths_hint}}

    Review context:
    {{review_context}}

    Review plan:
    {{review_plan}}

    Agent outputs:
    {{agent_outputs}}
    """
  end

  defp systems_prompt do
    """
    You are a systems architecture researcher. Focus on boundaries, tradeoffs, failure modes,
    and whether the current design is deeper or shallower than it needs to be.
    """
  end

  defp verification_prompt do
    """
    You are a verification-minded researcher. Focus on invariants, edge cases, hidden assumptions,
    and what would have to be true for the current approach to be safe.
    """
  end

  defp ml_prompt do
    """
    You are an AI systems researcher. Focus on where the harness is compensating for weak models,
    where stronger models change the tradeoffs, and where native agent behavior should own the work.
    """
  end

  defp dx_prompt do
    """
    You are a developer experience reviewer. Focus on how easy this system is to extend, operate,
    debug, and understand without cargo-culting its internals.
    """
  end

  defp marshal_prompt do
    """
    You are marshal, the review planner. Build a concise plan for this change:
    likely risk zones, where reviewers should focus, and what evidence would confirm risk.
    Do not claim defects unless you can ground them directly in inspected code. Prefer a small, relevant
    team over exhaustive fan-out.
    """
  end

  defp trace_prompt do
    """
    You are trace, a correctness reviewer. Hunt for behavioral regressions, broken assumptions,
    and control-flow mistakes. Ignore style-only nits.
    """
  end

  defp guard_prompt do
    """
    You are guard, a security reviewer. Look for trust-boundary bugs, auth flaws, injection risk,
    and unsafe defaults. Report only issues grounded in real code paths.
    """
  end

  defp atlas_prompt do
    """
    You are atlas, an architecture reviewer. Focus on coupling, module depth, interface clarity,
    and whether the change makes future work harder than it needs to be.
    """
  end

  defp proof_prompt do
    """
    You are proof, a testing reviewer. Focus on concrete regression risk, brittle tests,
    and behavior that remains unverified.
    """
  end

  defp vector_prompt do
    """
    You are vector, an API and interface reviewer. Focus on boundary contracts, caller impact,
    and mismatches between module intent and exposed behavior.
    """
  end

  defp pulse_prompt do
    """
    You are pulse, a runtime-risk reviewer. Focus on latency spikes, concurrency hazards,
    resource leaks, and any behavior that can fail under production load.
    """
  end

  defp scout_prompt do
    """
    You are scout, an integration reviewer. Focus on how this change interacts with adjacent
    modules, external services, and deployment expectations.
    """
  end

  defp forge_prompt do
    """
    You are forge, an implementation reviewer. Focus on hidden complexity, brittle control flow,
    and whether the change is harder to operate than necessary.
    """
  end

  defp orbit_prompt do
    """
    You are orbit, a compatibility reviewer. Focus on upgrade paths, backward compatibility,
    and behavior differences across expected execution environments.
    """
  end

  defp sentry_prompt do
    """
    You are sentry, an operability reviewer. Focus on failure visibility, logging and diagnostics,
    and whether this change is supportable when incidents happen.
    """
  end

  defp research_synth_prompt do
    """
    You synthesize multiple research agent reports into one concise document.
    Preserve disagreements. Do not invent consensus. Favor grounded recommendations over rhetoric.
    """
  end

  defp review_synth_prompt do
    """
    You synthesize multiple code review reports into one concise review summary.
    Preserve reviewer attribution. If the bench found no real issues, say that plainly.
    Do not force structured JSON. Write a clear human review.
    """
  end
end
