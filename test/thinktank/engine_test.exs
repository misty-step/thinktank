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

  test "preserves separate artifacts when the same agent runs twice" do
    cwd = unique_tmp_dir("thinktank-engine-duplicate-agents")

    runner = fn _cmd, _args, _opts -> {"ok", 0} end

    assert {:ok, result} =
             Engine.run(
               "research/default",
               %{input_text: "Research this", agents: ["systems", "systems"], no_synthesis: true},
               cwd: cwd,
               runner: runner
             )

    assert Enum.map(result.agents, & &1.name) == ["systems", "systems"]
    assert Enum.count(result.results) == 2
    assert Enum.map(result.envelope.agents, & &1["name"]) == ["systems", "systems"]

    files = Enum.map(result.envelope.agents, & &1["file"])
    assert length(Enum.uniq(files)) == 2
    assert Enum.all?(files, &File.exists?(Path.join(result.output_dir, &1)))
  end

  test "custom review benches emit review artifacts based on bench kind" do
    cwd = unique_tmp_dir("thinktank-engine-custom-review")
    config_path = Path.join([cwd, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      """
      benches:
        demo/custom-review:
          kind: review
          description: Demo custom review bench
          agents:
            - trace
          synthesizer: review-synth
          default_task: Review the current change and report only real issues with evidence.
      """
    )

    runner = fn _cmd, args, _opts ->
      prompt = File.read!(prompt_path(args))

      if String.contains?(prompt, "Agent outputs:") do
        {"Synthesized review\n\n" <> prompt, 0}
      else
        {"Raw agent report\n\n" <> prompt, 0}
      end
    end

    assert {:ok, result} =
             Engine.run(
               "demo/custom-review",
               %{},
               cwd: cwd,
               trust_repo_config: true,
               runner: runner
             )

    assert result.envelope.status == "complete"
    assert File.exists?(Path.join(result.output_dir, "review.md"))
    assert File.read!(Path.join(result.output_dir, "review.md")) =~ "Synthesized review"
    refute File.exists?(Path.join(result.output_dir, "synthesis.md"))
  end
end
