defmodule Thinktank.BenchSpecTest do
  use ExUnit.Case, async: true

  alias Thinktank.BenchSpec

  test "parses bench specs" do
    assert {:ok, bench} =
             BenchSpec.from_pair("review/default", %{
               "kind" => "review",
               "description" => "Review bench",
               "agents" => ["trace", "guard"],
               "planner" => "marshal",
               "synthesizer" => "review-synth",
               "concurrency" => "2",
               "default_task" => "Review this"
             })

    assert bench.id == "review/default"
    assert bench.kind == :review
    assert bench.agents == ["trace", "guard"]
    assert bench.planner == "marshal"
    assert bench.synthesizer == "review-synth"
    assert bench.concurrency == 2
  end

  test "rejects invalid bench specs" do
    for {raw, expected_error} <- [
          {%{"kind" => "mystery", "description" => "Custom bench", "agents" => ["trace"]},
           "bench kind must be one of: default, research, review"},
          {%{"description" => "Review bench", "agents" => []},
           "bench agents must be a non-empty list of agent names"},
          {%{"description" => "Review bench", "agents" => ["trace", 123]},
           "bench agents must be a non-empty list of agent names"},
          {%{"description" => "Review bench", "agents" => ["trace"], "default_task" => "   "},
           "bench optional string fields must be strings"}
        ] do
      assert {:error, ^expected_error} = BenchSpec.from_pair("review/default", raw)
    end
  end

  test "uses defaults for omitted optional fields" do
    assert {:ok, bench} =
             BenchSpec.from_pair("research/quick", %{
               "description" => "Quick research bench",
               "agents" => ["trace"]
             })

    assert bench.kind == :default
    assert bench.planner == nil
    assert bench.synthesizer == nil
    assert bench.concurrency == nil
    assert bench.default_task == nil
  end

  test "rejects non-map benches, missing descriptions, and invalid concurrency" do
    assert {:error, "bench review/default must be a map"} =
             BenchSpec.from_pair("review/default", nil)

    assert {:error, "bench description is required"} =
             BenchSpec.from_pair("review/default", %{"agents" => ["trace"]})

    assert {:error, "bench concurrency must be a positive integer"} =
             BenchSpec.from_pair("review/default", %{
               "description" => "Review bench",
               "agents" => ["trace"],
               "concurrency" => "0"
             })
  end
end
