defmodule Thinktank.StageSpecTest do
  use ExUnit.Case, async: true

  alias Thinktank.StageSpec

  test "parses supported stage kinds" do
    assert {:ok, stage} =
             StageSpec.from_map(%{
               "type" => "route",
               "kind" => "static_agents",
               "agents" => ["trace"]
             })

    assert stage.type == :route
    assert stage.kind == "static_agents"
  end

  test "rejects unsupported stage kinds for a type" do
    assert {:error, message} =
             StageSpec.from_map(%{
               "type" => "fanout",
               "kind" => "research_router"
             })

    assert message =~ "stage kind research_router is invalid for fanout"
  end

  test "parses numeric options and string when conditions" do
    assert {:ok, stage} =
             StageSpec.from_map(%{
               "type" => "fanout",
               "kind" => "agents",
               "retry" => "2",
               "concurrency" => "3",
               "when" => "agent_results"
             })

    assert stage.retry == 2
    assert stage.concurrency == 3
    assert stage.when == "agent_results"
  end
end
