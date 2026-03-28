defmodule Thinktank.BenchSpecTest do
  use ExUnit.Case, async: true

  alias Thinktank.BenchSpec

  test "parses bench specs" do
    assert {:ok, bench} =
             BenchSpec.from_pair("review/cerberus", %{
               "kind" => "review",
               "description" => "Review bench",
               "agents" => ["trace", "guard"],
               "synthesizer" => "review-synth",
               "concurrency" => "2",
               "default_task" => "Review this"
             })

    assert bench.id == "review/cerberus"
    assert bench.kind == :review
    assert bench.agents == ["trace", "guard"]
    assert bench.synthesizer == "review-synth"
    assert bench.concurrency == 2
  end

  test "rejects unknown bench kinds" do
    assert {:error, "bench kind must be one of: default, research, review"} =
             BenchSpec.from_pair("demo/custom", %{
               "kind" => "mystery",
               "description" => "Custom bench",
               "agents" => ["trace"]
             })
  end

  test "rejects empty agent lists" do
    assert {:error, "bench agents must be a non-empty list of agent names"} =
             BenchSpec.from_pair("review/cerberus", %{
               "description" => "Review bench",
               "agents" => []
             })
  end
end
