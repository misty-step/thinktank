defmodule Thinktank.EngineTest do
  use ExUnit.Case, async: false

  alias Thinktank.Engine

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp prompt_path(args) do
    index = Enum.find_index(args, &(&1 == "-p"))
    args |> Enum.at(index + 1) |> String.trim_leading("@")
  end

  test "runs a bench, records raw agent outputs, and writes a synthesized summary" do
    cwd = unique_tmp_dir("thinktank-engine")

    runner = fn _cmd, args, _opts ->
      path = prompt_path(args)
      prompt = File.read!(path)

      cond do
        String.contains?(prompt, "Agent outputs:") ->
          {"Synthesized summary\n\n" <> prompt, 0}

        true ->
          {"Raw agent report\n\n" <> prompt, 0}
      end
    end

    assert {:ok, result} =
             Engine.run(
               "review/cerberus",
               %{
                 input_text: "Review this branch",
                 base: "origin/main",
                 head: "HEAD",
                 repo: "misty-step/thinktank",
                 pr: 42,
                 paths: [cwd]
               },
               cwd: cwd,
               runner: runner
             )

    assert result.envelope.status == "complete"
    assert File.exists?(Path.join(result.output_dir, "review.md"))
    assert File.read!(Path.join(result.output_dir, "review.md")) =~ "Synthesized summary"
    assert Enum.count(result.results) == 4
  end

  test "marks the run as degraded when an agent fails" do
    cwd = unique_tmp_dir("thinktank-engine-degraded")

    runner = fn _cmd, args, _opts ->
      prompt = File.read!(prompt_path(args))

      if String.contains?(prompt, "You are guard") do
        {"guard failed", 1}
      else
        {"ok", 0}
      end
    end

    assert {:ok, result} =
             Engine.run(
               "review/cerberus",
               %{input_text: "Review this branch"},
               cwd: cwd,
               runner: runner
             )

    assert result.envelope.status == "degraded"
  end

  test "supports overriding a bench agent subset" do
    cwd = unique_tmp_dir("thinktank-engine-agents")

    runner = fn _cmd, _args, _opts -> {"ok", 0} end

    assert {:ok, result} =
             Engine.run(
               "research/default",
               %{input_text: "Research this", agents: ["systems", "dx"], no_synthesis: true},
               cwd: cwd,
               runner: runner
             )

    assert Enum.map(result.agents, & &1.name) == ["systems", "dx"]
    refute File.exists?(Path.join(result.output_dir, "synthesis.md"))
  end
end
