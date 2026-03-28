defmodule Thinktank.Review.PlannerTest do
  use ExUnit.Case, async: true

  alias Thinktank.{AgentSpec, Review.Planner}

  defp agent(name) do
    %AgentSpec{
      name: name,
      provider: "openrouter",
      model: "demo/model",
      system_prompt: "You are #{name}.",
      task_prompt: "{{input_text}}"
    }
  end

  test "manual planning keeps the bench roster intact" do
    agents = [agent("trace"), agent("guard"), agent("atlas"), agent("proof")]
    planning = Planner.manual(agents)

    assert planning.planner_result == nil
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
end
