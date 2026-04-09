defmodule Thinktank.Prompts.SynthesisTest do
  use ExUnit.Case, async: true

  alias Thinktank.Prompts.Synthesis

  test "research_task/0 contains required placeholders" do
    task = Synthesis.research_task()

    for placeholder <- ~w({{input_text}} {{workspace_root}} {{paths_hint}} {{agent_outputs}}) do
      assert task =~ placeholder, "research synthesis task missing #{placeholder}"
    end
  end

  test "review_task/0 contains required placeholders" do
    task = Synthesis.review_task()

    for placeholder <-
          ~w(
            {{input_text}}
            {{workspace_root}}
            {{repo}}
            {{pr}}
            {{base}}
            {{head}}
            {{paths_hint}}
            {{review_context}}
            {{review_plan}}
            {{synthesis_brief}}
            {{agent_outputs}}
          ) do
      assert task =~ placeholder, "review synthesis task missing #{placeholder}"
    end
  end

  for name <- [:research_system, :review_system] do
    test "#{name}/0 returns a non-empty binary" do
      result = apply(Synthesis, unquote(name), [])
      assert is_binary(result) and byte_size(result) > 0
    end
  end
end
