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
end
