defmodule Thinktank.WorkflowSpecTest do
  use ExUnit.Case, async: true

  alias Thinktank.WorkflowSpec

  test "accepts constrained stage graphs in order" do
    assert {:ok, workflow} =
             WorkflowSpec.from_pair("demo/workflow", %{
               "description" => "Demo workflow",
               "stages" => [
                 %{"type" => "prepare", "kind" => "research_input"},
                 %{"type" => "route", "kind" => "static_agents"},
                 %{"type" => "fanout", "kind" => "agents"},
                 %{"type" => "aggregate", "kind" => "research_synthesis"},
                 %{"type" => "emit", "kind" => "artifacts"},
                 %{"name" => "final_emit", "type" => "emit", "kind" => "artifacts"}
               ]
             })

    assert workflow.id == "demo/workflow"
    assert Enum.at(workflow.stages, 5).name == "final_emit"
  end

  test "rejects stage graphs that skip required phases" do
    assert {:error, "workflow stages must include prepare, route, fanout, emit"} =
             WorkflowSpec.from_pair("demo/workflow", %{
               "description" => "Broken workflow",
               "stages" => [
                 %{"type" => "prepare", "kind" => "research_input"},
                 %{"type" => "emit", "kind" => "artifacts"}
               ]
             })
  end

  test "rejects stage graphs that go backwards" do
    assert {:error,
            "workflow stages must follow prepare -> route -> fanout -> aggregate -> emit order"} =
             WorkflowSpec.from_pair("demo/workflow", %{
               "description" => "Broken workflow",
               "stages" => [
                 %{"type" => "prepare", "kind" => "research_input"},
                 %{"type" => "route", "kind" => "static_agents"},
                 %{"type" => "fanout", "kind" => "agents"},
                 %{"type" => "emit", "kind" => "artifacts"},
                 %{"type" => "aggregate", "kind" => "research_synthesis"}
               ]
             })
  end
end
