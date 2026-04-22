defmodule Thinktank.RunInspector do
  @moduledoc """
  Reads durable run artifacts and exposes inspection helpers for CLI commands.
  """

  alias Thinktank.{ArtifactLayout, RunTracker, TraceLog}

  @known_statuses ~w(running complete degraded partial failed)
  @terminal_statuses ~w(complete degraded partial failed)
  @default_poll_ms 100
  @default_limit 20

  @type run_info :: %{
          id: String.t(),
          output_dir: String.t(),
          bench: String.t() | nil,
          kind: String.t() | nil,
          status: String.t(),
          started_at: String.t() | nil,
          completed_at: String.t() | nil,
          workspace_root: String.t() | nil,
          manifest_file: String.t() | nil,
          trace_summary_file: String.t() | nil,
          trace_events_file: String.t() | nil
        }

  @spec list(keyword()) :: {:ok, [run_info()]}
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    runs =
      opts
      |> discover_output_dirs()
      |> Enum.map(&load_run(&1, :lenient))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn {:ok, run} -> run end)
      |> Enum.sort_by(&{sort_timestamp(&1), &1.id, &1.output_dir}, :desc)
      |> maybe_limit(limit)

    {:ok, runs}
  end

  @spec show(String.t(), keyword()) :: {:ok, run_info()} | {:error, String.t()}
  def show(target, opts \\ []) when is_binary(target) do
    with {:ok, output_dir} <- resolve_target(target, opts) do
      load_run(output_dir)
    end
  end

  @spec wait(String.t(), keyword()) :: {:ok, run_info()} | {:error, String.t()}
  def wait(target, opts \\ []) when is_binary(target) do
    poll_ms = Keyword.get(opts, :poll_ms, @default_poll_ms)
    timeout_ms = Keyword.get(opts, :timeout_ms, :infinity)

    with {:ok, output_dir} <- resolve_target(target, opts) do
      wait_for_terminal(output_dir, poll_ms, deadline_after(timeout_ms))
    end
  end

  @spec terminal_status?(String.t()) :: boolean()
  def terminal_status?(status) when is_binary(status), do: status in @terminal_statuses

  defp wait_for_terminal(output_dir, poll_ms, deadline) do
    case load_run(output_dir) do
      {:ok, %{status: status} = run} when status in @terminal_statuses ->
        {:ok, run}

      {:ok, _run} ->
        if timed_out?(deadline) do
          {:error, "timed out waiting for run to finish: #{output_dir}"}
        else
          Process.sleep(poll_ms)
          wait_for_terminal(output_dir, poll_ms, deadline)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp resolve_target(target, opts) do
    case resolve_target_path(target) do
      {:ok, output_dir} ->
        {:ok, output_dir}

      :not_a_path_target ->
        resolve_target_id(target, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_target_id(target, opts) do
    matches =
      opts
      |> discover_output_dirs()
      |> Enum.filter(&(Path.basename(&1) == target))

    case matches do
      [output_dir] ->
        {:ok, output_dir}

      [] ->
        {:error, "run not found: #{target}"}

      _ ->
        {:error, "multiple runs match #{target}; use an explicit path"}
    end
  end

  defp resolve_target_path(target) do
    if path_target?(target) do
      target
      |> Path.expand()
      |> resolve_existing_path(target)
    else
      :not_a_path_target
    end
  end

  defp resolve_existing_path(expanded, original_target) do
    candidate =
      cond do
        File.dir?(expanded) -> expanded
        File.exists?(expanded) -> run_dir_from_artifact_path(expanded)
        true -> :missing
      end

    cond do
      candidate == :missing ->
        {:error, "run not found: #{original_target}"}

      run_dir?(candidate) ->
        {:ok, candidate}

      true ->
        {:error, "not a ThinkTank run directory: #{original_target}"}
    end
  end

  defp run_dir_from_artifact_path(path) do
    cond do
      String.ends_with?(path, "/" <> ArtifactLayout.manifest_file()) ->
        Path.dirname(path)

      String.ends_with?(path, "/" <> ArtifactLayout.contract_file()) ->
        Path.dirname(path)

      String.ends_with?(path, "/" <> TraceLog.summary_file()) ->
        path |> Path.dirname() |> Path.dirname()

      String.ends_with?(path, "/" <> TraceLog.events_file()) ->
        path |> Path.dirname() |> Path.dirname()

      true ->
        nil
    end
  end

  defp path_target?(target) do
    String.contains?(target, ["/", "\\"]) || String.starts_with?(target, ".") ||
      String.starts_with?(target, "~")
  end

  defp discover_output_dirs(opts) do
    [
      tracked_output_dirs(),
      tmp_output_dirs(Keyword.get(opts, :tmp_dir, System.tmp_dir!())),
      log_output_dirs(Keyword.get(opts, :log_dir, TraceLog.global_log_dir()))
    ]
    |> List.flatten()
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp tracked_output_dirs do
    Enum.map(RunTracker.active_runs(), fn {output_dir, _attrs} -> output_dir end)
  end

  defp tmp_output_dirs(tmp_dir) do
    [
      Path.join(tmp_dir, "thinktank-*"),
      Path.join(tmp_dir, "thinktank-*/*")
    ]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&run_dir?/1)
  end

  defp log_output_dirs(nil), do: []

  defp log_output_dirs(log_dir) do
    if File.dir?(log_dir) do
      log_dir
      |> Path.join("*.jsonl")
      |> Path.wildcard()
      |> Enum.sort(:desc)
      |> Enum.flat_map(&read_log_output_dirs/1)
    else
      []
    end
  end

  defp read_log_output_dirs(path) do
    path
    |> File.stream!(:line, [])
    |> Enum.reduce([], fn line, acc ->
      case Jason.decode(line) do
        {:ok, %{"output_dir" => output_dir}} when is_binary(output_dir) ->
          [output_dir | acc]

        _ ->
          acc
      end
    end)
  rescue
    _ -> []
  end

  defp run_dir?(output_dir) do
    File.exists?(Path.join(output_dir, ArtifactLayout.manifest_file())) ||
      File.exists?(Path.join(output_dir, TraceLog.summary_file()))
  end

  defp load_run(output_dir, mode \\ :strict) do
    case do_load_run(Path.expand(output_dir)) do
      {:ok, run} -> {:ok, run}
      {:error, _reason} when mode == :lenient -> nil
      {:error, _reason} = error -> error
    end
  end

  defp do_load_run(output_dir) do
    paths = run_paths(output_dir)

    with {:ok, manifest} <- read_json_optional(paths.manifest),
         {:ok, summary} <- read_json_optional(paths.summary),
         {:ok, contract} <- read_json_optional(paths.contract),
         :ok <- ensure_run_artifacts(output_dir, manifest, summary, contract),
         {:ok, status} <- derive_status(manifest, summary) do
      {:ok, build_run_info(output_dir, paths, manifest, summary, contract, status)}
    end
  end

  defp ensure_run_artifacts(output_dir, nil, nil, nil),
    do: {:error, "run artifacts not found: #{output_dir}"}

  defp ensure_run_artifacts(_output_dir, _manifest, _summary, _contract), do: :ok

  defp derive_status(manifest, summary) do
    case manifest_value(manifest, "status") || manifest_value(summary, "status") do
      status when status in @known_statuses -> {:ok, status}
      nil -> {:error, "run status is missing"}
      status -> {:error, "unknown run status: #{inspect(status)}"}
    end
  end

  defp read_json_optional(path) do
    if File.exists?(path), do: read_json_file(path), else: {:ok, nil}
  end

  defp read_json_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- decode_json_object(body, path) do
      {:ok, decoded}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "failed to read #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp decode_json_object(body, path) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _decoded} -> {:error, "expected JSON object at #{path}"}
      {:error, reason} -> {:error, "failed to decode #{path}: #{Exception.message(reason)}"}
    end
  end

  defp build_run_info(output_dir, paths, manifest, summary, contract, status) do
    bench =
      manifest_value(manifest, "bench") ||
        manifest_value(summary, "bench") ||
        manifest_value(contract, "bench_id")

    %{
      id: Path.basename(output_dir),
      output_dir: output_dir,
      bench: bench,
      kind: manifest_value(manifest, "kind") || infer_kind(bench),
      status: status,
      started_at: manifest_value(manifest, "started_at") || manifest_value(summary, "started_at"),
      completed_at:
        manifest_value(manifest, "completed_at") || manifest_value(summary, "completed_at"),
      workspace_root:
        manifest_value(manifest, "workspace_root") || manifest_value(contract, "workspace_root"),
      manifest_file: existing_path(paths.manifest),
      trace_summary_file: existing_path(paths.summary),
      trace_events_file: existing_path(paths.events)
    }
  end

  defp run_paths(output_dir) do
    %{
      manifest: Path.join(output_dir, ArtifactLayout.manifest_file()),
      summary: Path.join(output_dir, TraceLog.summary_file()),
      events: Path.join(output_dir, TraceLog.events_file()),
      contract: Path.join(output_dir, ArtifactLayout.contract_file())
    }
  end

  defp manifest_value(nil, _key), do: nil
  defp manifest_value(map, key), do: Map.get(map, key)

  defp existing_path(path), do: if(File.exists?(path), do: path, else: nil)

  defp infer_kind(nil), do: nil

  defp infer_kind(bench_id) when is_binary(bench_id) do
    cond do
      String.starts_with?(bench_id, "review/") -> "review"
      String.starts_with?(bench_id, "research/") -> "research"
      true -> nil
    end
  end

  defp sort_timestamp(run), do: run.started_at || run.completed_at || ""

  defp maybe_limit(runs, nil), do: runs
  defp maybe_limit(runs, limit) when is_integer(limit) and limit >= 0, do: Enum.take(runs, limit)

  defp deadline_after(:infinity), do: :infinity

  defp deadline_after(timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0 do
    System.monotonic_time(:millisecond) + timeout_ms
  end

  defp timed_out?(:infinity), do: false
  defp timed_out?(deadline), do: System.monotonic_time(:millisecond) >= deadline
end
