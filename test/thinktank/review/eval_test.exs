defmodule Thinktank.Review.EvalTest do
  use ExUnit.Case, async: false

  alias Thinktank.{Error, Review.Eval, RunContract}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp git!(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true, env: [{"LEFTHOOK", "0"}]) do
      {_output, 0} -> :ok
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed (#{status}): #{output}")
    end
  end

  defp init_git_repo_with_commit!(cwd) do
    git!(cwd, ["init"])
    git!(cwd, ["config", "user.email", "thinktank@example.com"])
    git!(cwd, ["config", "user.name", "ThinkTank Test"])
    File.write!(Path.join(cwd, ".gitkeep"), "")
    git!(cwd, ["add", "."])
    git!(cwd, ["commit", "-m", "initial"])
  end

  test "replays one or more frozen contract files" do
    workspace = unique_tmp_dir("thinktank-review-eval-workspace")
    init_git_repo_with_commit!(workspace)
    fixture_root = unique_tmp_dir("thinktank-review-eval-fixtures")
    output_root = Path.join(unique_tmp_dir("thinktank-review-eval-output"), "runs")

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
    workspace = unique_tmp_dir("thinktank-review-eval-historical")
    init_git_repo_with_commit!(workspace)
    fixture_root = unique_tmp_dir("thinktank-review-eval-historical-fixtures")
    output_root = Path.join(unique_tmp_dir("thinktank-review-eval-historical-output"), "runs")

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

  test "returns typed case and top-level errors when replay cases fail" do
    workspace = unique_tmp_dir("thinktank-review-eval-failing")
    init_git_repo_with_commit!(workspace)
    fixture_root = unique_tmp_dir("thinktank-review-eval-failing-fixtures")
    output_root = Path.join(unique_tmp_dir("thinktank-review-eval-failing-output"), "runs")

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
    workspace = unique_tmp_dir("thinktank-review-eval-degraded")
    init_git_repo_with_commit!(workspace)
    fixture_root = unique_tmp_dir("thinktank-review-eval-degraded-fixtures")
    output_root = Path.join(unique_tmp_dir("thinktank-review-eval-degraded-output"), "runs")

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
    success_workspace = unique_tmp_dir("thinktank-review-eval-mixed-success")
    failing_workspace = unique_tmp_dir("thinktank-review-eval-mixed-failing")
    init_git_repo_with_commit!(success_workspace)
    init_git_repo_with_commit!(failing_workspace)
    fixture_root = unique_tmp_dir("thinktank-review-eval-mixed-fixtures")
    output_root = Path.join(unique_tmp_dir("thinktank-review-eval-mixed-output"), "runs")

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
               "synthesis_brief" => "Prefer grounded findings."
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
end
