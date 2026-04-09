defmodule Thinktank.Review.Eval do
  @moduledoc false

  alias Thinktank.{Config, Engine, Error, RunContract}

  @type result :: %{
          target: String.t(),
          status: String.t(),
          output_dir: String.t(),
          artifacts: [map()],
          error: Error.t() | nil,
          cases: [map()]
        }

  @spec run(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(target, opts \\ []) when is_binary(target) do
    with {:ok, contract_paths} <- contract_paths(target),
         {:ok, contracts} <- load_contracts(contract_paths) do
      output_dir = Keyword.get(opts, :output, Engine.generate_output_dir("review-eval"))

      cases =
        contracts
        |> Enum.with_index(1)
        |> Enum.map(fn {{contract_path, contract}, index} ->
          run_case(index, contract_path, contract, output_dir, opts)
        end)

      summary = summarize_cases(cases, output_dir)

      {:ok,
       %{
         target: target,
         status: summary.status,
         output_dir: output_dir,
         artifacts: summary.artifacts,
         error: summary.error,
         cases: cases
       }}
    end
  end

  defp run_case(index, contract_path, contract, output_dir, opts) do
    bench_id = Keyword.get(opts, :bench_id) || "review/default"
    case_id = "case-#{String.pad_leading(Integer.to_string(index), 3, "0")}"
    case_output = Path.join(output_dir, case_id)

    run_opts =
      [cwd: contract.workspace_root, output: case_output]
      |> Keyword.put(:adapter_context, contract.adapter_context)
      |> maybe_put_opt(:trust_repo_config, Keyword.get(opts, :trust_repo_config))
      |> maybe_put_opt(
        :agent_config_dir,
        Keyword.get(opts, :agent_config_dir) || agent_config_dir(contract.workspace_root)
      )
      |> maybe_put_opt(:runner, Keyword.get(opts, :runner))

    case Engine.run(bench_id, contract.input, run_opts) do
      {:ok, result} ->
        %{
          case_id: case_id,
          contract: contract_path,
          bench: bench_id,
          status: result.envelope.status,
          output_dir: result.output_dir,
          error: nil
        }

      {:error, %Error{} = reason, failed_output_dir} ->
        %{
          case_id: case_id,
          contract: contract_path,
          bench: bench_id,
          status: "failed",
          output_dir: failed_output_dir || case_output,
          error: reason
        }
    end
  end

  defp contract_paths(target) do
    expanded = Path.expand(target)

    cond do
      File.regular?(expanded) ->
        {:ok, [expanded]}

      File.dir?(expanded) ->
        case Path.wildcard(Path.join(expanded, "**/contract.json")) |> Enum.sort() do
          [] -> {:error, "no contract.json files found under #{expanded}"}
          paths -> {:ok, paths}
        end

      true ->
        {:error, "path does not exist: #{expanded}"}
    end
  end

  defp load_contracts(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      with {:ok, raw} <- File.read(path),
           {:ok, decoded} <- Jason.decode(raw),
           {:ok, contract} <- RunContract.from_map(decoded) do
        {:cont, {:ok, [{path, contract} | acc]}}
      else
        {:error, reason} ->
          {:halt, {:error, "failed to load #{path}: #{inspect(reason)}"}}
      end
    end)
    |> case do
      {:ok, contracts} -> {:ok, Enum.reverse(contracts)}
      error -> error
    end
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp summarize_cases(cases, output_dir) do
    summary =
      Enum.reduce(cases, initial_summary(), fn case_result, acc ->
        acc
        |> summarize_status(case_result.status)
        |> maybe_add_artifact(case_result, output_dir)
      end)

    status =
      cond do
        summary.all_complete? -> "complete"
        summary.any_non_failed_case? -> "degraded"
        true -> "failed"
      end

    %{
      status: status,
      artifacts: Enum.reverse(summary.artifacts),
      error: summarize_error(status, summary)
    }
  end

  defp initial_summary do
    %{
      all_complete?: true,
      any_non_failed_case?: false,
      failed_cases: 0,
      degraded_cases: 0,
      artifacts: []
    }
  end

  defp summarize_status(summary, "complete") do
    %{summary | any_non_failed_case?: true}
  end

  defp summarize_status(summary, "degraded") do
    %{
      summary
      | all_complete?: false,
        any_non_failed_case?: true,
        degraded_cases: summary.degraded_cases + 1
    }
  end

  defp summarize_status(summary, "failed") do
    %{summary | all_complete?: false, failed_cases: summary.failed_cases + 1}
  end

  defp summarize_status(summary, _status) do
    %{summary | all_complete?: false}
  end

  defp maybe_add_artifact(summary, case_result, output_dir) do
    case artifact_for(case_result, output_dir) do
      nil -> summary
      artifact -> %{summary | artifacts: [artifact | summary.artifacts]}
    end
  end

  defp artifact_for(case_result, output_dir) do
    if is_binary(case_result.output_dir) and File.exists?(case_result.output_dir) do
      %{
        name: case_result.case_id,
        file: Path.relative_to(case_result.output_dir, output_dir),
        type: "directory"
      }
    end
  end

  defp summarize_error("complete", _summary), do: nil

  defp summarize_error("degraded", summary) do
    Error.from_contract(:review_eval_degraded, %{
      failed_cases: summary.failed_cases,
      degraded_cases: summary.degraded_cases
    })
  end

  defp summarize_error("failed", summary) do
    Error.from_contract(:review_eval_failed, %{
      failed_cases: summary.failed_cases
    })
  end

  defp agent_config_dir(workspace_root) do
    if Config.trust_repo_agent_config?() do
      dir = Path.join(workspace_root, "agent_config")
      if File.dir?(dir), do: dir
    end
  end
end
