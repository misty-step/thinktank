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

  test "rejects conflicting default and execution modes" do
    assert {:error, "workflow default_mode quick conflicts with execution_mode deep"} =
             WorkflowSpec.from_pair("demo/workflow", %{
               "description" => "Broken workflow",
               "default_mode" => "quick",
               "execution_mode" => "deep",
               "stages" => [
                 %{"type" => "prepare", "kind" => "research_input"},
                 %{"type" => "route", "kind" => "static_agents"},
                 %{"type" => "fanout", "kind" => "agents"},
                 %{"type" => "emit", "kind" => "artifacts"}
               ]
             })
  end

  test "rejects duplicate stateful phases" do
    assert {:error, "workflow stages may not repeat route"} =
             WorkflowSpec.from_pair("demo/workflow", %{
               "description" => "Broken workflow",
               "stages" => [
                 %{"type" => "prepare", "kind" => "research_input"},
                 %{"type" => "route", "kind" => "static_agents"},
                 %{"type" => "route", "kind" => "static_agents"},
                 %{"type" => "fanout", "kind" => "agents"},
                 %{"type" => "emit", "kind" => "artifacts"}
               ]
             })
  end
end
