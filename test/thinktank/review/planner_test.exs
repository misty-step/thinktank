defmodule Thinktank.Review.PlannerTest do
  use ExUnit.Case, async: true

  alias Thinktank.{AgentSpec, Config, ProviderSpec, Review.Planner, RunContract}

  defp agent(name) do
    %AgentSpec{
      name: name,
      provider: "openrouter",
      model: "demo/model",
      system_prompt: "You are #{name}.",
      thinking_level: "high",
      task_prompt: "{{input_text}}"
    }
  end

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp planner_config do
    %Config{
      providers: %{
        "openrouter" => %ProviderSpec{
          id: "openrouter",
          adapter: :openrouter,
          credential_env: "THINKTANK_OPENROUTER_API_KEY",
          defaults: %{}
        }
      },
      agents: %{},
      benches: %{},
      sources: %{}
    }
  end

  defp planner_result_for(output) do
    workspace = unique_tmp_dir("thinktank-planner-test")

    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: workspace,
      artifact_dir: workspace,
      input: %{"input_text" => "Review this branch"},
      adapter_context: %{}
    }

    reviewer_agents = [agent("trace"), agent("guard"), agent("atlas")]
    planner_agent = agent("marshal")
    review_context = %{"version" => 1, "change" => %{"files" => ["lib/demo.ex"]}}

    Planner.create(
      planner_agent,
      reviewer_agents,
      contract,
      review_context,
      planner_config(),
      runner: fn _cmd, _args, _opts -> {output, 0} end
    )
  end

  test "manual planning keeps the bench roster intact" do
    agents = [agent("trace"), agent("guard"), agent("atlas"), agent("proof")]
    planning = Planner.manual(agents)

    assert planning.planner_result == nil
    assert planning.fallback_reason == nil
    assert planning.plan["source"] == "manual"

    assert Enum.map(planning.plan["selected_agents"], & &1["name"]) == [
             "trace",
             "guard",
             "atlas",
             "proof"
           ]
  end

  test "render includes selected reviewer names" do
    agents = [agent("trace"), agent("guard")]
    planning = Planner.manual(agents)
    rendered = Planner.render(planning.plan)

    assert rendered =~ "trace"
    assert rendered =~ "guard"
  end

  test "applies per-agent reviewer briefs to task prompts" do
    agents = [agent("trace"), agent("guard")]

    plan = %{
      "selected_agents" => [
        %{"name" => "guard", "brief" => "security focus"},
        %{"name" => "trace", "brief" => "correctness focus"}
      ]
    }

    planned = Planner.apply_plan(plan, agents)

    assert Enum.map(planned, & &1.name) == ["guard", "trace"]

    assert Enum.map(planned, &get_in(&1.metadata, ["review_brief"])) == [
             "security focus",
             "correctness focus"
           ]
  end

  test "falls back when planner output contains unsupported top-level keys" do
    planning =
      planner_result_for(
        Jason.encode!(%{
          "summary" => "Focus correctness.",
          "selected_agents" => [%{"name" => "trace", "brief" => "Check regressions."}],
          "synthesis_brief" => "Prefer grounded findings.",
          "warnings" => [],
          "extra_key" => "not allowed"
        })
      )

    assert planning.plan["source"] == "fallback"

    assert planning.fallback_reason ==
             "planner output rejected: plan has unsupported keys: extra_key"
  end

  test "falls back when planner output selects duplicate reviewers" do
    planning =
      planner_result_for(
        Jason.encode!(%{
          "summary" => "Focus correctness.",
          "selected_agents" => [
            %{"name" => "trace", "brief" => "First brief."},
            %{"name" => "trace", "brief" => "Second brief."}
          ],
          "synthesis_brief" => "Prefer grounded findings.",
          "warnings" => []
        })
      )

    assert planning.plan["source"] == "fallback"

    assert planning.fallback_reason ==
             "planner output rejected: selected_agents must not contain duplicates: trace"
  end

  test "falls back when planner output has invalid warnings" do
    planning =
      planner_result_for(
        Jason.encode!(%{
          "summary" => "Focus correctness.",
          "selected_agents" => [%{"name" => "trace", "brief" => "Check regressions."}],
          "synthesis_brief" => "Prefer grounded findings.",
          "warnings" => [123]
        })
      )

    assert planning.plan["source"] == "fallback"

    assert planning.fallback_reason ==
             "planner output rejected: warnings entries must be non-empty strings"
  end
end
