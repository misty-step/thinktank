defmodule Thinktank.Review.EvalTest do
  use ExUnit.Case, async: false

  alias Thinktank.{Review.Eval, RunContract}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  test "replays one or more frozen contract files" do
    workspace = unique_tmp_dir("thinktank-review-eval-workspace")
    fixture_root = unique_tmp_dir("thinktank-review-eval-fixtures")
    output_root = Path.join(unique_tmp_dir("thinktank-review-eval-output"), "runs")

    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: workspace,
      input: %{"input_text" => "Review the current change"},
      artifact_dir: Path.join(fixture_root, "source-run"),
      adapter_context: %{}
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
    assert length(result.cases) == 2
    assert Enum.all?(result.cases, &(&1.status == "complete"))
    assert Enum.all?(result.cases, &File.exists?(Path.join(&1.output_dir, "review/plan.json")))
  end

  test "replays a historical contract with a removed bench_id through review/default" do
    workspace = unique_tmp_dir("thinktank-review-eval-historical")
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
    assert Enum.all?(result.cases, &(&1.bench == "review/default"))
  end
end
