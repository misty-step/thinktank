defmodule Thinktank.EngineTest do
  use ExUnit.Case, async: false

  alias Thinktank.{Engine, Error, RunTracker}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp read_jsonl(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
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

  defp init_git_repo_with_commit!(cwd) do
    init_git_repo!(cwd)
    File.write!(Path.join(cwd, ".gitkeep"), "")
    git!(cwd, ["add", "."])
    git!(cwd, ["commit", "-m", "initial"])
  end

  test "runs a bench, records raw agent outputs, and writes a synthesized summary" do
    cwd = unique_tmp_dir("thinktank-engine")
    init_git_repo_with_commit!(cwd)

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
             "synthesis_brief" => "Prioritize reviewer overlap and grounded defects.",
             "warnings" => []
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
    assert result.envelope.synthesis =~ "Synthesized summary"
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
    init_git_repo_with_commit!(cwd)

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

  test "marks the run as partial when an agent times out and keeps a best-effort summary" do
    cwd = unique_tmp_dir("thinktank-engine-partial")
    init_git_repo_with_commit!(cwd)

    runner = fn _cmd, _args, _opts -> {"partial finding", :timeout} end

    assert {:ok, result} =
             Engine.run(
               "research/default",
               %{input_text: "Research this", agents: ["systems"], no_synthesis: true},
               cwd: cwd,
               runner: runner
             )

    assert result.envelope.status == "partial"
    assert File.read!(Path.join(result.output_dir, "summary.md")) =~ "Partial Result"
    assert File.read!(Path.join(result.output_dir, "summary.md")) =~ "partial finding"
    assert File.exists?(Path.join(result.output_dir, "scratchpads/run.md"))
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

    init_git_repo_with_commit!(cwd)

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
           "synthesis_brief" => "Prefer grounded defects.",
           "warnings" => []
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
    assert Enum.any?(prompts, &(File.read!(&1) =~ "\"selected_agents\""))
    assert Enum.any?(prompts, &(File.read!(&1) =~ "\"change\""))
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

  test "review planner rejects non-JSON responses and records fallback trace events" do
    cwd = unique_tmp_dir("thinktank-engine-planner-fallback")
    init_git_repo_with_commit!(cwd)

    runner = fn _cmd, args, _opts ->
      prompt = File.read!(prompt_path(args))

      if String.contains?(prompt, "Return JSON only with this shape:") do
        {"```json\n{\"summary\":\"Focus correctness.\",\"selected_agents\":[{\"name\":\"trace\",\"brief\":\"Check regressions.\"}],\"synthesis_brief\":\"Prefer grounded evidence.\",\"warnings\":[]}\n```",
         0}
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

    plan = result.output_dir |> Path.join("review/plan.json") |> File.read!() |> Jason.decode!()
    assert plan["source"] == "fallback"

    assert Enum.any?(plan["warnings"], fn warning ->
             String.contains?(
               warning,
               "planner output rejected: planner output must be valid JSON"
             )
           end)

    events = read_jsonl(Path.join(result.output_dir, "trace/events.jsonl"))

    assert Enum.any?(events, fn event ->
             event["event"] == "review_planner_fallback" and
               String.contains?(
                 to_string(event["reason"]),
                 "planner output rejected: planner output must be valid JSON"
               )
           end)
  end

  test "review optional markdown artifact write failures are non-gating and traced" do
    cwd = unique_tmp_dir("thinktank-engine-review-optional-artifacts")
    output_dir = Path.join(cwd, "captured-run")
    init_git_repo_with_commit!(cwd)

    File.mkdir_p!(Path.join(output_dir, "review/context.md"))

    runner = fn _cmd, args, _opts ->
      prompt = File.read!(prompt_path(args))

      if String.contains?(prompt, "Return JSON only with this shape:") do
        {Jason.encode!(%{
           "summary" => "Focus on correctness.",
           "selected_agents" => [%{"name" => "trace", "brief" => "Check regressions."}],
           "synthesis_brief" => "Use grounded evidence.",
           "warnings" => []
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
               output: output_dir,
               runner: runner
             )

    assert result.envelope.status == "complete"
    assert File.exists?(Path.join(output_dir, "review/context.json"))
    assert File.exists?(Path.join(output_dir, "review/plan.json"))

    events = read_jsonl(Path.join(output_dir, "trace/events.jsonl"))

    assert Enum.any?(events, fn event ->
             event["event"] == "review_optional_artifact_write_failed" and
               event["artifact_file"] == "review/context.md"
           end)
  end

  test "review bench fails early when workspace has no git repository" do
    cwd = unique_tmp_dir("thinktank-engine-review-no-git")
    runner = fn _cmd, _args, _opts -> {"ok", 0} end

    assert {:error, %Error{code: :no_git_repository}, _output_dir} =
             Engine.run(
               "review/default",
               %{input_text: "Review this branch"},
               cwd: cwd,
               runner: runner
             )
  end

  test "run emits lifecycle trace events with the final status" do
    cwd = unique_tmp_dir("thinktank-engine-trace")
    output_dir = Path.join(cwd, "captured-run")
    init_git_repo_with_commit!(cwd)

    runner = fn _cmd, _args, _opts -> {"ok", 0} end

    assert {:ok, result} =
             Engine.run(
               "research/default",
               %{input_text: "Research this", no_synthesis: true},
               cwd: cwd,
               output: output_dir,
               runner: runner
             )

    assert result.output_dir == output_dir

    events = read_jsonl(Path.join(output_dir, "trace/events.jsonl"))

    assert Enum.any?(events, fn event ->
             event["event"] == "run_started" and event["bench"] == "research/default"
           end)

    assert Enum.any?(events, fn event ->
             event["event"] == "planned_agents_selected" and
               event["agent_names"] == Enum.map(result.agents, & &1.name)
           end)

    assert Enum.any?(events, fn event ->
             event["event"] == "run_completed" and event["status"] == "complete"
           end)

    assert RunTracker.active_runs() == []
  end

  test "run_resolved emits progress callback phases while agents execute" do
    cwd = unique_tmp_dir("thinktank-engine-progress")
    output_dir = Path.join(cwd, "progress-run")
    init_git_repo_with_commit!(cwd)

    runner = fn _cmd, _args, _opts ->
      Process.sleep(40)
      {"ok", 0}
    end

    assert {:ok, resolved} =
             Engine.resolve(
               "research/default",
               %{input_text: "Research this", no_synthesis: true},
               cwd: cwd,
               output: output_dir
             )

    parent = self()
    progress_callback = fn event, attrs -> send(parent, {:progress, event, attrs}) end

    assert {:ok, result} =
             Engine.run_resolved(
               resolved,
               runner: runner,
               progress_callback: progress_callback
             )

    assert result.output_dir == output_dir

    assert_receive {:progress, "bootstrap_started", %{"output_dir" => ^output_dir}}, 1_000

    assert_receive {:progress, "agent_started",
                    %{"agent_name" => "systems", "phase" => "running_agents"}},
                   1_000

    assert_receive {:progress, "agent_finished",
                    %{"agent_name" => "systems", "status" => "ok", "phase" => "running_agents"}},
                   1_000

    assert_receive {:progress, "run_completed",
                    %{
                      "output_dir" => ^output_dir,
                      "status" => "complete",
                      "phase" => "finalizing"
                    }},
                   1_000
  end

  test "run emits progress callbacks before completion" do
    cwd = unique_tmp_dir("thinktank-engine-progress")
    output_dir = Path.expand(Path.join(cwd, "captured-run"))
    init_git_repo_with_commit!(cwd)
    parent = self()

    runner = fn _cmd, _args, _opts ->
      Process.sleep(150)
      {"ok", 0}
    end

    task =
      Task.async(fn ->
        Engine.run(
          "research/default",
          %{input_text: "Research this", agents: ["systems"], no_synthesis: true},
          cwd: cwd,
          output: output_dir,
          runner: runner,
          progress_callback: fn event, attrs ->
            send(parent, {:progress, event, attrs})
          end
        )
      end)

    assert_receive {:progress, "bootstrap_started", %{"output_dir" => ^output_dir}}, 1_000

    assert_receive {:progress, "agent_started",
                    %{"agent_name" => "systems", "phase" => "running_agents"}},
                   1_000

    assert_receive {:progress, "agent_finished",
                    %{"agent_name" => "systems", "status" => "ok", "phase" => "running_agents"}},
                   1_000

    assert_receive {:progress, "run_completed",
                    %{
                      "output_dir" => ^output_dir,
                      "status" => "complete",
                      "phase" => "finalizing"
                    }},
                   1_000

    assert {:ok, result} = Task.await(task)
    assert result.output_dir == output_dir
  end

  test "review runs emit planning progress before reviewer execution" do
    cwd = unique_tmp_dir("thinktank-engine-review-progress")
    output_dir = Path.expand(Path.join(cwd, "captured-run"))
    init_git_repo_with_commit!(cwd)
    parent = self()

    runner = fn _cmd, args, _opts ->
      prompt = File.read!(prompt_path(args))

      if String.contains?(prompt, "Return JSON only with this shape:") do
        {Jason.encode!(%{
           "summary" => "Focus on correctness.",
           "selected_agents" => [%{"name" => "trace", "brief" => "Check regressions."}],
           "synthesis_brief" => "Use grounded evidence.",
           "warnings" => []
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
               output: output_dir,
               runner: runner,
               progress_callback: fn event, attrs ->
                 send(parent, {:progress, event, attrs})
               end
             )

    assert result.envelope.status == "complete"

    assert_receive {:progress, "prepare_started",
                    %{"output_dir" => ^output_dir, "phase" => "planning"}},
                   1_000

    assert_receive {:progress, "agent_started",
                    %{"agent_name" => "marshal", "phase" => "planning"}},
                   1_000

    assert_receive {:progress, "agents_started", %{"phase" => "running_agents"}}, 1_000
  end

  test "synthesizer progress keeps the synthesizer phase" do
    cwd = unique_tmp_dir("thinktank-engine-synthesis-progress")
    output_dir = Path.expand(Path.join(cwd, "captured-run"))
    init_git_repo_with_commit!(cwd)
    parent = self()

    runner = fn _cmd, args, _opts ->
      prompt = File.read!(prompt_path(args))

      if String.contains?(prompt, "Agent outputs:") do
        {"Synthesized summary", 0}
      else
        {"ok", 0}
      end
    end

    assert {:ok, result} =
             Engine.run(
               "research/default",
               %{input_text: "Research this", agents: ["systems"]},
               cwd: cwd,
               output: output_dir,
               runner: runner,
               progress_callback: fn event, attrs ->
                 send(parent, {:progress, event, attrs})
               end
             )

    assert result.envelope.status == "complete"

    assert_receive {:progress, "synthesis_started",
                    %{"phase" => "synthesizing", "synthesizer" => "research-synth"}},
                   1_000

    assert_receive {:progress, "agent_started",
                    %{"agent_name" => "research-synth", "phase" => "synthesizing"}},
                   1_000
  end

  test "failed runs emit error progress and failed completion" do
    cwd = unique_tmp_dir("thinktank-engine-failed-progress")
    output_dir = Path.expand(Path.join(cwd, "captured-run"))
    init_git_repo_with_commit!(cwd)
    parent = self()

    runner = fn _cmd, _args, _opts -> {"simulated failure", 1} end

    assert {:error, %Error{code: :no_successful_agents}, ^output_dir} =
             Engine.run(
               "research/default",
               %{input_text: "Research this", agents: ["systems"], no_synthesis: true},
               cwd: cwd,
               output: output_dir,
               runner: runner,
               progress_callback: fn event, attrs ->
                 send(parent, {:progress, event, attrs})
               end
             )

    assert_receive {:progress, "agent_finished",
                    %{"agent_name" => "systems", "phase" => "running_agents", "status" => "error"}},
                   1_000

    assert_receive {:progress, "run_completed",
                    %{"output_dir" => ^output_dir, "phase" => "finalizing", "status" => "failed"}},
                   1_000
  end

  test "degraded runs emit degraded completion progress" do
    cwd = unique_tmp_dir("thinktank-engine-degraded-progress")
    output_dir = Path.expand(Path.join(cwd, "captured-run"))
    init_git_repo_with_commit!(cwd)
    parent = self()

    runner = fn _cmd, args, _opts ->
      prompt_file = Path.basename(prompt_path(args))

      if String.starts_with?(prompt_file, "systems-") do
        {"ok", 0}
      else
        {"simulated failure", 1}
      end
    end

    assert {:ok, result} =
             Engine.run(
               "research/default",
               %{input_text: "Research this", agents: ["systems", "dx"], no_synthesis: true},
               cwd: cwd,
               output: output_dir,
               runner: runner,
               progress_callback: fn event, attrs ->
                 send(parent, {:progress, event, attrs})
               end
             )

    assert result.envelope.status == "degraded"

    assert_receive {:progress, "agent_finished",
                    %{"agent_name" => "systems", "phase" => "running_agents", "status" => "ok"}},
                   1_000

    assert_receive {:progress, "agent_finished",
                    %{"agent_name" => "dx", "phase" => "running_agents", "status" => "error"}},
                   1_000

    assert_receive {:progress, "run_completed",
                    %{
                      "output_dir" => ^output_dir,
                      "phase" => "finalizing",
                      "status" => "degraded"
                    }},
                   1_000
  end

  test "bootstrap failures before run initialization are recorded in the global log" do
    cwd = unique_tmp_dir("thinktank-engine-bootstrap")
    log_dir = unique_tmp_dir("thinktank-engine-bootstrap-logs")
    output_dir = Path.join(cwd, "blocked-output")
    previous_log_dir = System.get_env("THINKTANK_LOG_DIR")

    File.write!(output_dir, "not a directory")
    System.put_env("THINKTANK_LOG_DIR", log_dir)

    on_exit(fn ->
      if is_nil(previous_log_dir) do
        System.delete_env("THINKTANK_LOG_DIR")
      else
        System.put_env("THINKTANK_LOG_DIR", previous_log_dir)
      end
    end)

    init_git_repo_with_commit!(cwd)

    runner = fn _cmd, _args, _opts -> flunk("runner should not execute when bootstrap fails") end

    assert {:error, %Error{} = error, ^output_dir} =
             Engine.run(
               "research/default",
               %{input_text: "Research this", no_synthesis: true},
               cwd: cwd,
               output: output_dir,
               runner: runner
             )

    assert error.code == :bootstrap_failed
    assert error.message == "failed to initialize run artifacts"
    assert error.details[:phase] == "init_run"
    assert error.details[:output_dir] == output_dir
    assert error.details[:input][:input_text_bytes] == 13

    [global_log] = Path.wildcard(Path.join(log_dir, "*.jsonl"))
    [event] = read_jsonl(global_log)

    assert event["event"] == "bootstrap_failed"
    assert event["phase"] == "init_run"
    assert event["bench"] == "research/default"
    assert event["output_dir"] == output_dir
    assert event["error"]["category"] == "bootstrap_failed"
    assert event["error"]["message"] =~ "not a directory"

    refute File.exists?(Path.join(output_dir, "manifest.json"))
    assert RunTracker.active_runs() == []
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
