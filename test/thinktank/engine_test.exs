defmodule Thinktank.EngineTest do
  use ExUnit.Case, async: false

  alias Thinktank.{Engine, Error}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp prompt_path(args) do
    index = Enum.find_index(args, &(&1 == "-p"))
    args |> Enum.at(index + 1) |> String.trim_leading("@")
  end

  defp git!(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true, env: [{"LEFTHOOK", "0"}]) do
      {output, 0} -> output
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed (#{status}): #{output}")
    end
  end

  defp init_git_repo!(cwd) do
    git!(cwd, ["init"])
    git!(cwd, ["config", "user.email", "thinktank@example.com"])
    git!(cwd, ["config", "user.name", "ThinkTank Test"])
  end

  test "runs a bench, records raw agent outputs, and writes a synthesized summary" do
    cwd = unique_tmp_dir("thinktank-engine")

    runner = fn _cmd, args, _opts ->
      path = prompt_path(args)
      prompt = File.read!(path)

      cond do
        String.contains?(prompt, "Return JSON only with this shape:") ->
          {Jason.encode!(%{
             "summary" => "Focus the bench on correctness, architecture, and tests.",
             "selected_agents" => [
               %{
                 "name" => "trace",
                 "brief" => "Focus on behavioral regressions in the changed paths."
               },
               %{"name" => "atlas", "brief" => "Focus on coupling and boundary changes."},
               %{"name" => "proof", "brief" => "Focus on regression coverage gaps."}
             ],
             "synthesis_brief" => "Prioritize reviewer overlap and grounded defects."
           }), 0}

        String.contains?(prompt, "Agent outputs:") ->
          {"Synthesized summary\n\n" <> prompt, 0}

        true ->
          {"Raw agent report\n\n" <> prompt, 0}
      end
    end

    assert {:ok, result} =
             Engine.run(
               "review/default",
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
    assert Enum.map(result.agents, & &1.name) == ["trace", "atlas", "proof"]
    assert Enum.count(result.results) == 3
    assert File.exists?(Path.join(result.output_dir, "review/context.json"))
    assert File.exists?(Path.join(result.output_dir, "review/plan.json"))
    assert File.exists?(Path.join(result.output_dir, "review/planner.md"))
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
               "review/default",
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

  test "review runs write context and plan artifacts and focus the reviewer subset" do
    cwd = unique_tmp_dir("thinktank-engine-focused-review")
    init_git_repo!(cwd)

    File.mkdir_p!(Path.join(cwd, "lib"))
    File.write!(Path.join(cwd, "lib/demo.ex"), "defmodule Demo do\n  def run, do: :ok\nend\n")
    git!(cwd, ["add", "."])
    git!(cwd, ["commit", "-m", "initial"])

    File.write!(
      Path.join(cwd, "lib/demo.ex"),
      "defmodule Demo do\n  def run, do: :updated\nend\n"
    )

    runner = fn _cmd, args, _opts ->
      prompt = File.read!(prompt_path(args))

      if String.contains?(prompt, "Return JSON only with this shape:") do
        {Jason.encode!(%{
           "summary" => "Keep the bench focused on correctness and architecture.",
           "selected_agents" => [
             %{"name" => "trace", "brief" => "Check behavioral regressions."},
             %{"name" => "atlas", "brief" => "Check boundary and coupling changes."}
           ],
           "synthesis_brief" => "Prefer grounded defects."
         }), 0}
      else
        {"ok", 0}
      end
    end

    assert {:ok, result} =
             Engine.run(
               "review/default",
               %{input_text: "Review this branch", no_synthesis: true},
               cwd: cwd,
               runner: runner
             )

    assert File.exists?(Path.join(result.output_dir, "review/context.json"))
    assert File.exists?(Path.join(result.output_dir, "review/plan.json"))
    assert File.exists?(Path.join(result.output_dir, "review/context.md"))
    assert File.exists?(Path.join(result.output_dir, "review/plan.md"))

    plan = result.output_dir |> Path.join("review/plan.json") |> File.read!() |> Jason.decode!()
    selected = Enum.map(plan["selected_agents"], & &1["name"])

    assert selected == Enum.map(result.agents, & &1.name)
    assert selected == ["trace", "atlas"]
    assert Enum.member?(selected, "trace")
    assert plan["source"] == "planner"

    prompts = Path.wildcard(Path.join(result.output_dir, "prompts/*.md"))
    assert prompts != []
    assert Enum.any?(prompts, &(File.read!(&1) =~ "Assigned brief:"))
  end

  test "review planner preserves explicit reviewer overrides" do
    cwd = unique_tmp_dir("thinktank-engine-explicit-review")
    init_git_repo!(cwd)

    File.mkdir_p!(Path.join(cwd, "lib"))
    File.write!(Path.join(cwd, "lib/demo.ex"), "defmodule Demo do\n  def run, do: :ok\nend\n")
    git!(cwd, ["add", "."])
    git!(cwd, ["commit", "-m", "initial"])

    File.write!(
      Path.join(cwd, "lib/demo.ex"),
      "defmodule Demo do\n  def run, do: :updated\nend\n"
    )

    runner = fn _cmd, _args, _opts -> {"ok", 0} end

    assert {:ok, result} =
             Engine.run(
               "review/default",
               %{input_text: "Review this branch", agents: ["guard"], no_synthesis: true},
               cwd: cwd,
               runner: runner
             )

    assert Enum.map(result.agents, & &1.name) == ["guard"]

    plan = result.output_dir |> Path.join("review/plan.json") |> File.read!() |> Jason.decode!()
    assert plan["source"] == "manual"
    assert Enum.map(plan["selected_agents"], & &1["name"]) == ["guard"]
  end

  test "does not replace malformed input_text with a bench default task" do
    cwd = unique_tmp_dir("thinktank-engine-invalid-input")
    config_path = Path.join([cwd, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      """
      benches:
        demo/custom:
          description: Demo bench
          agents:
            - trace
          default_task: Investigate the workspace
      """
    )

    assert {:error, %Error{code: :missing_input_text}, nil} =
             Engine.resolve(
               "demo/custom",
               %{input_text: 123},
               cwd: cwd,
               trust_repo_config: true
             )
  end
end
