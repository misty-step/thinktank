defmodule Thinktank.Review.Eval do
  @moduledoc false

  alias Thinktank.{Config, Engine, RunContract}

  @type result :: %{
          target: String.t(),
          status: String.t(),
          output_dir: String.t(),
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

      {:ok,
       %{
         target: target,
         status: derive_status(cases),
         output_dir: output_dir,
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
          output_dir: result.output_dir
        }

      {:error, reason, failed_output_dir} ->
        %{
          case_id: case_id,
          contract: contract_path,
          bench: bench_id,
          status: "failed",
          output_dir: failed_output_dir || case_output,
          error: format_reason(reason)
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

  defp derive_status(cases) do
    statuses = Enum.map(cases, & &1.status)

    cond do
      Enum.all?(statuses, &(&1 == "complete")) -> "complete"
      Enum.any?(statuses, &(&1 in ["complete", "degraded"])) -> "degraded"
      true -> "failed"
    end
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp agent_config_dir(workspace_root) do
    if Config.trust_repo_agent_config?() do
      dir = Path.join(workspace_root, "agent_config")
      if File.dir?(dir), do: dir
    end
  end

  defp format_reason(%Thinktank.Error{message: message}), do: message
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
