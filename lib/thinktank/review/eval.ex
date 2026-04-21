defmodule Thinktank.Review.Eval do
  @moduledoc false

  alias Thinktank.{ArtifactLayout, Config, Engine, Error, RunContract, TraceLog}

  @terminal_run_statuses ~w(complete degraded partial failed)

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

    run_opts = [
      cwd: contract.workspace_root,
      output: case_output,
      adapter_context: contract.adapter_context,
      trust_repo_config: Keyword.get(opts, :trust_repo_config),
      agent_config_dir:
        Keyword.get(opts, :agent_config_dir) || agent_config_dir(contract.workspace_root),
      runner: Keyword.get(opts, :runner)
    ]

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
        contract_paths_from_directory(expanded)

      true ->
        {:error, "path does not exist: #{expanded}"}
    end
  end

  defp contract_paths_from_directory(directory) do
    case run_contract_path(directory) do
      {:ok, nil} -> wildcard_contract_paths(directory)
      {:ok, contract_path} -> {:ok, [contract_path]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_contract_path(directory) do
    contract_path = Path.join(directory, ArtifactLayout.contract_file())
    manifest_path = Path.join(directory, ArtifactLayout.manifest_file())
    trace_summary_path = Path.join(directory, TraceLog.summary_file())

    if File.regular?(contract_path) and
         (File.regular?(manifest_path) or File.regular?(trace_summary_path)) do
      normalize_run_directory(directory, contract_path, manifest_path, trace_summary_path)
    else
      {:ok, nil}
    end
  end

  defp normalize_run_directory(directory, contract_path, manifest_path, trace_summary_path) do
    with {:ok, run_state} <- read_run_state(directory, manifest_path, trace_summary_path) do
      if terminal_run_state?(run_state) do
        {:ok, contract_path}
      else
        {:error, in_progress_error(run_state)}
      end
    end
  end

  defp read_run_state(directory, manifest_path, trace_summary_path) do
    with {:ok, manifest_status} <- read_status(manifest_path, "manifest"),
         {:ok, trace_status} <- read_status(trace_summary_path, "trace summary") do
      {:ok,
       %{
         path: directory,
         manifest_status: manifest_status,
         trace_status: trace_status
       }}
    end
  end

  defp read_status(path, label) do
    cond do
      not is_binary(path) ->
        {:ok, nil}

      not File.regular?(path) ->
        {:ok, nil}

      true ->
        case load_json_map(path) do
          {:ok, decoded} ->
            {:ok, normalize_status(Map.get(decoded, "status"))}

          {:error, reason} ->
            {:error, "failed to load #{label} at #{path}: #{reason}"}
        end
    end
  end

  defp load_json_map(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, decoded} <- Jason.decode(raw),
         true <- is_map(decoded) do
      {:ok, decoded}
    else
      false -> {:error, "expected a JSON object"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp normalize_status(status) when is_binary(status), do: String.trim(status)
  defp normalize_status(_status), do: nil

  defp terminal_run_state?(run_state) do
    terminal_status?(run_state.manifest_status) or terminal_status?(run_state.trace_status)
  end

  defp terminal_status?(status) when is_binary(status), do: status in @terminal_run_statuses
  defp terminal_status?(_status), do: false

  defp in_progress_error(run_state) do
    Error.from_reason(%{
      category: :review_eval_in_progress,
      message: "review run is still in progress; wait for terminal run state before replaying",
      path: run_state.path,
      manifest_status: run_state.manifest_status,
      trace_status: run_state.trace_status
    })
  end

  defp wildcard_contract_paths(directory) do
    contract_file = ArtifactLayout.contract_file()

    case Path.wildcard(Path.join(directory, "**/" <> contract_file)) |> Enum.sort() do
      [] -> {:error, "no #{contract_file} files found under #{directory}"}
      paths -> {:ok, paths}
    end
  end

  defp load_contracts(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      with {:ok, decoded} <- load_json_map(path),
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
