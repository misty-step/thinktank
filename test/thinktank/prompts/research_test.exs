defmodule Thinktank.Prompts.ResearchTest do
  use ExUnit.Case, async: true

  alias Thinktank.Prompts.Research

  test "task/0 contains required placeholders" do
    task = Research.task()

    for placeholder <- ~w({{input_text}} {{workspace_root}} {{paths_hint}}) do
      assert task =~ placeholder, "task prompt missing #{placeholder}"
    end
  end

  for name <- [:systems, :verification, :ml, :dx] do
    test "#{name}/0 returns a non-empty binary" do
      result = apply(Research, unquote(name), [])
      assert is_binary(result) and byte_size(result) > 0
    end
  end
end
