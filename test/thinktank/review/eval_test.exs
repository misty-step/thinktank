defmodule Thinktank.Review.EvalTest do
  use ExUnit.Case, async: false

  alias Thinktank.{BenchSpec, Error, Review.Eval, RunContract, RunStore}
  alias Thinktank.Test.Workspace

  test "replays one or more frozen contract files" do
    workspace = Workspace.unique_tmp_dir("thinktank-review-eval-workspace")
    Workspace.init_git_repo!(workspace)
    fixture_root = Workspace.unique_tmp_dir("thinktank-review-eval-fixtures")
    output_root = Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-output"), "runs")

    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: workspace,
      input: %{"input_text" => "Review the current change"},
      artifact_dir: Path.join(fixture_root, "source-run"),
      adapter_context: %{"source" => "frozen-contract"}
    }

    first = Path.join([fixture_root, "one", "contract.json"])
    second = Path.join([fixture_root, "two", "contract.json"])
    File.mkdir_p!(Path.dirname(first))
    File.mkdir_p!(Path.dirname(second))
    File.write!(first, Jason.encode!(RunContract.to_map(contract)))
    File.write!(second, Jason.encode!(RunContract.to_map(contract)))

    runner = fn _cmd, args, _opts ->
      prompt =
        args
        |> Enum.drop_while(&(&1 != "-p"))
        |> Enum.at(1)
        |> String.trim_leading("@")
        |> File.read!()

      cond do
        String.contains?(prompt, "Return JSON only with this shape:") ->
          {Jason.encode!(%{
             "summary" => "Keep the default bench small.",
             "selected_agents" => [
               %{"name" => "trace", "brief" => "Check correctness risks."},
               %{"name" => "proof", "brief" => "Check coverage gaps."}
             ],
             "synthesis_brief" => "Prefer grounded findings."
           }), 0}

        String.contains?(prompt, "Agent outputs:") ->
          {"Synthesized summary", 0}

        true ->
          {"Raw reviewer output", 0}
      end
    end

    assert {:ok, result} =
             Eval.run(fixture_root,
               output: output_root,
               bench_id: "review/default",
               runner: runner
             )

    assert result.status == "complete"
    assert result.error == nil

    assert [
             %{file: "case-001", name: "case-001", type: "directory"},
             %{
               file: "case-002",
               name: "case-002",
               type: "directory"
             }
           ] = result.artifacts

    assert length(result.cases) == 2
    assert Enum.all?(result.cases, &(&1.status == "complete"))
    assert Enum.all?(result.cases, &File.exists?(Path.join(&1.output_dir, "review/plan.json")))

    replayed_contract =
      output_root
      |> Path.join("case-001/contract.json")
      |> File.read!()
      |> Jason.decode!()

    assert replayed_contract["adapter_context"] == %{"source" => "frozen-contract"}
  end

  test "replays a historical contract with a removed bench_id through review/default" do
    workspace = Workspace.unique_tmp_dir("thinktank-review-eval-historical")
    Workspace.init_git_repo!(workspace)
    fixture_root = Workspace.unique_tmp_dir("thinktank-review-eval-historical-fixtures")

    output_root =
      Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-historical-output"), "runs")

    contract = %RunContract{
      bench_id: "review/cerberus",
      workspace_root: workspace,
      input: %{"input_text" => "Review the current change"},
      artifact_dir: Path.join(fixture_root, "source-run"),
      adapter_context: %{}
    }

    path = Path.join([fixture_root, "historical", "contract.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(RunContract.to_map(contract)))

    runner = fn _cmd, args, _opts ->
      prompt =
        args
        |> Enum.drop_while(&(&1 != "-p"))
        |> Enum.at(1)
        |> String.trim_leading("@")
        |> File.read!()

      cond do
        String.contains?(prompt, "Return JSON only with this shape:") ->
          {Jason.encode!(%{
             "summary" => "Historical replay.",
             "selected_agents" => [
               %{"name" => "trace", "brief" => "Check regressions."}
             ],
             "synthesis_brief" => "Consolidate findings."
           }), 0}

        String.contains?(prompt, "Agent outputs:") ->
          {"Synthesized", 0}

        true ->
          {"ok", 0}
      end
    end

    assert {:ok, result} =
             Eval.run(fixture_root,
               output: output_root,
               runner: runner
             )

    assert result.status == "complete"
    assert result.error == nil
    assert Enum.all?(result.cases, &(&1.bench == "review/default"))
  end

  test "replays a direct contract.json path" do
    workspace = Workspace.unique_tmp_dir("thinktank-review-eval-direct-path")
    Workspace.init_git_repo!(workspace)
    fixture_root = Workspace.unique_tmp_dir("thinktank-review-eval-direct-path-fixtures")

    output_root =
      Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-direct-path-output"), "runs")

    contract_path = Path.join([fixture_root, "single", "contract.json"])
    contract = review_contract(workspace, Path.join(fixture_root, "source-run"))
    write_contract(contract_path, contract)

    assert {:ok, result} =
             Eval.run(contract_path,
               output: output_root,
               runner: successful_runner()
             )

    assert result.status == "complete"
    assert [%{contract: ^contract_path, status: "complete"}] = result.cases
  end

  test "treats a directory without run markers as a saved-contract collection" do
    workspace = Workspace.unique_tmp_dir("thinktank-review-eval-saved-contract-dir")
    Workspace.init_git_repo!(workspace)
    fixture_root = Workspace.unique_tmp_dir("thinktank-review-eval-saved-contract-fixtures")

    output_root =
      Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-saved-output"), "runs")

    contract_path = Path.join(fixture_root, "contract.json")
    contract = review_contract(workspace, Path.join(fixture_root, "source-run"))
    write_contract(contract_path, contract)

    assert {:ok, result} =
             Eval.run(fixture_root,
               output: output_root,
               runner: successful_runner()
             )

    assert result.status == "complete"
    assert [%{contract: ^contract_path, status: "complete"}] = result.cases
  end

  for terminal_status <- ~w(complete degraded partial failed) do
    test "replays a finished review run directory with #{terminal_status} terminal status" do
      workspace = Workspace.unique_tmp_dir("thinktank-review-eval-finished-workspace")
      Workspace.init_git_repo!(workspace)

      source_run =
        Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-finished-source"), "run")

      output_root =
        Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-finished-output"), "runs")

      contract =
        review_contract(workspace, source_run, %{
          "source" => "finished-run",
          "status" => unquote(terminal_status)
        })

      RunStore.init_run(source_run, contract, review_bench())
      RunStore.complete_run(source_run, unquote(terminal_status))

      assert {:ok, result} =
               Eval.run(source_run,
                 output: output_root,
                 runner: successful_runner()
               )

      contract_path = Path.join(source_run, "contract.json")

      assert result.status == "complete"
      assert [%{contract: ^contract_path, status: "complete"}] = result.cases

      replayed_contract =
        output_root
        |> Path.join("case-001/contract.json")
        |> File.read!()
        |> Jason.decode!()

      assert replayed_contract["adapter_context"] == %{
               "source" => "finished-run",
               "status" => unquote(terminal_status)
             }
    end
  end

  test "returns a typed error for an in-progress review run directory" do
    workspace = Workspace.unique_tmp_dir("thinktank-review-eval-live-workspace")
    Workspace.init_git_repo!(workspace)
    source_run = Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-live-source"), "run")

    contract = review_contract(workspace, source_run)
    RunStore.init_run(source_run, contract, review_bench())

    assert {:error,
            %Error{
              code: :review_eval_in_progress,
              details: %{
                path: resolved_path,
                manifest_status: "running",
                trace_status: "running"
              }
            }} = Eval.run(source_run)

    assert resolved_path == Path.expand(source_run)
  end

  test "accepts a terminal trace summary even when the manifest is still running" do
    workspace = Workspace.unique_tmp_dir("thinktank-review-eval-trace-terminal-workspace")
    Workspace.init_git_repo!(workspace)

    source_run =
      Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-trace-terminal-source"), "run")

    output_root =
      Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-trace-terminal-output"), "runs")

    contract = review_contract(workspace, source_run, %{"source" => "trace-terminal"})
    RunStore.init_run(source_run, contract, review_bench())
    Thinktank.TraceLog.complete_run(source_run, %{"status" => "partial"})

    assert {:ok, result} =
             Eval.run(source_run,
               output: output_root,
               runner: successful_runner()
             )

    assert result.status == "complete"
  end

  test "returns typed case and top-level errors when replay cases fail" do
    workspace = Workspace.unique_tmp_dir("thinktank-review-eval-failing")
    Workspace.init_git_repo!(workspace)
    fixture_root = Workspace.unique_tmp_dir("thinktank-review-eval-failing-fixtures")

    output_root =
      Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-failing-output"), "runs")

    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: workspace,
      input: %{"input_text" => "Review the current change"},
      artifact_dir: Path.join(fixture_root, "source-run"),
      adapter_context: %{}
    }

    path = Path.join([fixture_root, "failing", "contract.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(RunContract.to_map(contract)))

    runner = fn _cmd, _args, _opts -> {"planner failed", 1} end

    assert {:ok, result} =
             Eval.run(fixture_root,
               output: output_root,
               runner: runner
             )

    assert result.status == "failed"
    assert %Error{code: :review_eval_failed} = result.error
    assert [%{file: "case-001", name: "case-001", type: "directory"}] = result.artifacts
    assert [%{status: "failed", error: %Error{code: :no_successful_agents}}] = result.cases
  end

  test "returns a typed degraded error when replay cases degrade without failing" do
    workspace = Workspace.unique_tmp_dir("thinktank-review-eval-degraded")
    Workspace.init_git_repo!(workspace)
    fixture_root = Workspace.unique_tmp_dir("thinktank-review-eval-degraded-fixtures")

    output_root =
      Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-degraded-output"), "runs")

    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: workspace,
      input: %{"input_text" => "Review the current change"},
      artifact_dir: Path.join(fixture_root, "source-run"),
      adapter_context: %{}
    }

    path = Path.join([fixture_root, "degraded", "contract.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(RunContract.to_map(contract)))

    runner = fn _cmd, args, _opts ->
      prompt =
        args
        |> Enum.drop_while(&(&1 != "-p"))
        |> Enum.at(1)
        |> String.trim_leading("@")
        |> File.read!()

      if String.contains?(prompt, "You are guard") do
        {"guard failed", 1}
      else
        {"ok", 0}
      end
    end

    assert {:ok, result} =
             Eval.run(fixture_root,
               output: output_root,
               runner: runner
             )

    assert result.status == "degraded"

    assert %Error{code: :review_eval_degraded, details: %{failed_cases: 0, degraded_cases: 1}} =
             result.error

    assert [%{file: "case-001", name: "case-001", type: "directory"}] = result.artifacts
    assert [%{status: "degraded", error: nil}] = result.cases
  end

  test "returns a typed degraded error when replay cases are mixed" do
    success_workspace = Workspace.unique_tmp_dir("thinktank-review-eval-mixed-success")
    failing_workspace = Workspace.unique_tmp_dir("thinktank-review-eval-mixed-failing")
    Workspace.init_git_repo!(success_workspace)
    Workspace.init_git_repo!(failing_workspace)
    fixture_root = Workspace.unique_tmp_dir("thinktank-review-eval-mixed-fixtures")

    output_root =
      Path.join(Workspace.unique_tmp_dir("thinktank-review-eval-mixed-output"), "runs")

    success_contract = %RunContract{
      bench_id: "review/default",
      workspace_root: success_workspace,
      input: %{"input_text" => "Review the current change"},
      artifact_dir: Path.join(fixture_root, "success-run"),
      adapter_context: %{}
    }

    failing_contract = %RunContract{
      bench_id: "review/default",
      workspace_root: failing_workspace,
      input: %{"input_text" => "Review the current change"},
      artifact_dir: Path.join(fixture_root, "failing-run"),
      adapter_context: %{}
    }

    success_path = Path.join([fixture_root, "one", "contract.json"])
    failing_path = Path.join([fixture_root, "two", "contract.json"])
    File.mkdir_p!(Path.dirname(success_path))
    File.mkdir_p!(Path.dirname(failing_path))
    File.write!(success_path, Jason.encode!(RunContract.to_map(success_contract)))
    File.write!(failing_path, Jason.encode!(RunContract.to_map(failing_contract)))

    runner = fn _cmd, args, opts ->
      prompt =
        args
        |> Enum.drop_while(&(&1 != "-p"))
        |> Enum.at(1)
        |> String.trim_leading("@")
        |> File.read!()

      if opts[:cd] == success_workspace do
        cond do
          String.contains?(prompt, "Return JSON only with this shape:") ->
            {Jason.encode!(%{
               "summary" => "Mixed replay success.",
               "selected_agents" => [
                 %{"name" => "trace", "brief" => "Check regressions."}
               ],
               "synthesis_brief" => "Prefer grounded findings.",
               "warnings" => []
             }), 0}

          String.contains?(prompt, "Agent outputs:") ->
            {"Synthesized summary", 0}

          true ->
            {"Raw reviewer output", 0}
        end
      else
        {"planner failed", 1}
      end
    end

    assert {:ok, result} =
             Eval.run(fixture_root,
               output: output_root,
               runner: runner
             )

    assert result.status == "degraded"
    assert %Error{code: :review_eval_degraded} = result.error
    assert Enum.map(result.cases, & &1.status) == ["complete", "failed"]
  end

  defp review_contract(workspace_root, artifact_dir, adapter_context \\ %{}) do
    %RunContract{
      bench_id: "review/default",
      workspace_root: workspace_root,
      input: %{"input_text" => "Review the current change"},
      artifact_dir: artifact_dir,
      adapter_context: adapter_context
    }
  end

  defp review_bench do
    %BenchSpec{id: "review/default", kind: :review, description: "Review", agents: ["trace"]}
  end

  defp write_contract(path, %RunContract{} = contract) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(RunContract.to_map(contract)))
  end

  defp successful_runner do
    fn _cmd, args, _opts ->
      prompt =
        args
        |> Enum.drop_while(&(&1 != "-p"))
        |> Enum.at(1)
        |> String.trim_leading("@")
        |> File.read!()

      cond do
        String.contains?(prompt, "Return JSON only with this shape:") ->
          {Jason.encode!(%{
             "summary" => "Replay succeeded.",
             "selected_agents" => [
               %{"name" => "trace", "brief" => "Check correctness risks."}
             ],
             "synthesis_brief" => "Prefer grounded findings.",
             "warnings" => []
           }), 0}

        String.contains?(prompt, "Agent outputs:") ->
          {"Synthesized summary", 0}

        true ->
          {"Raw reviewer output", 0}
      end
    end
  end
end
