defmodule Thinktank.RunInspector do
  @moduledoc """
  Reads durable run artifacts and exposes inspection helpers for CLI commands.
  """

  alias Thinktank.{ArtifactLayout, Error, RunTracker, TraceLog}

  @known_statuses ~w(running complete degraded partial failed)
  @terminal_statuses ~w(complete degraded partial failed)
  @transient_wait_error_codes [
    :run_artifacts_missing,
    :run_artifact_read_error,
    :run_artifact_decode_error,
    :run_status_missing
  ]
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

  @spec list(keyword()) :: {:ok, [run_info()]} | {:error, Error.t()}
  def list(opts \\ []) do
    with {:ok, limit} <- list_limit(opts) do
      {:ok, load_listed_runs(opts, limit)}
    end
  end

  @spec show(String.t(), keyword()) :: {:ok, run_info()} | {:error, Error.t()}
  def show(target, opts \\ []) when is_binary(target) do
    with {:ok, output_dir} <- resolve_target(target, opts) do
      load_run(output_dir)
    end
  end

  @spec wait(String.t(), keyword()) :: {:ok, run_info()} | {:error, Error.t()}
  def wait(target, opts \\ []) when is_binary(target) do
    poll_ms = Keyword.get(opts, :poll_ms, @default_poll_ms)
    timeout_ms = Keyword.get(opts, :timeout_ms, :infinity)

    with {:ok, output_dir} <- resolve_target(target, opts) do
      wait_for_terminal(output_dir, poll_ms, deadline_after(timeout_ms))
    end
  end

  @spec terminal_status?(String.t()) :: boolean()
  def terminal_status?(status) when is_binary(status), do: status in @terminal_statuses

  @spec input_error?(Error.t()) :: boolean()
  def input_error?(%Error{code: code})
      when code in [
             :run_target_not_found,
             :run_target_ambiguous,
             :invalid_run_target,
             :invalid_run_list_limit
           ],
      do: true

  def input_error?(_error), do: false

  defp wait_for_terminal(output_dir, poll_ms, deadline) do
    case load_run(output_dir) do
      {:ok, %{status: status} = run} when status in @terminal_statuses ->
        {:ok, run}

      {:ok, _run} ->
        sleep_or_timeout(output_dir, poll_ms, deadline)

      {:error, %Error{code: code}} when code in @transient_wait_error_codes ->
        sleep_or_timeout(output_dir, poll_ms, deadline)

      {:error, _reason} = error ->
        error
    end
  end

  defp sleep_or_timeout(output_dir, poll_ms, deadline) do
    if timed_out?(deadline) do
      error(:run_wait_timeout, "timed out waiting for run to finish: #{output_dir}",
        output_dir: output_dir
      )
    else
      Process.sleep(poll_ms)
      wait_for_terminal(output_dir, poll_ms, deadline)
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
        error(:run_target_not_found, "run not found: #{target}", target: target)

      _ ->
        error(
          :run_target_ambiguous,
          "multiple runs match #{target}; use an explicit path",
          target: target
        )
    end
  end

  defp resolve_target_path(target) do
    expanded = Path.expand(target)

    cond do
      File.dir?(expanded) ->
        validate_run_dir(expanded, target)

      File.exists?(expanded) ->
        expanded
        |> run_dir_from_artifact_path()
        |> validate_run_dir(target)

      path_target?(target) ->
        error(:run_target_not_found, "run not found: #{target}", target: target)

      true ->
        :not_a_path_target
    end
  end

  defp run_dir_from_artifact_path(path) do
    trace_dir = TraceLog.summary_file() |> Path.dirname()
    basename = Path.basename(path)
    parent_dir = path |> Path.dirname() |> Path.basename()

    cond do
      basename in [ArtifactLayout.manifest_file(), ArtifactLayout.contract_file()] ->
        Path.dirname(path)

      parent_dir == trace_dir and
          basename in [
            Path.basename(TraceLog.summary_file()),
            Path.basename(TraceLog.events_file())
          ] ->
        path |> Path.dirname() |> Path.dirname()

      true ->
        nil
    end
  end

  defp validate_run_dir(nil, original_target) do
    error(
      :invalid_run_target,
      "not a ThinkTank run directory: #{original_target}",
      target: original_target
    )
  end

  defp validate_run_dir(output_dir, original_target) do
    if run_dir?(output_dir) do
      {:ok, output_dir}
    else
      error(
        :invalid_run_target,
        "not a ThinkTank run directory: #{original_target}",
        target: original_target
      )
    end
  end

  defp path_target?(target) do
    String.contains?(target, ["/", "\\"]) || String.starts_with?(target, ".") ||
      String.starts_with?(target, "~")
  end

  defp discover_output_dirs(opts) do
    tmp_dir = Keyword.get(opts, :tmp_dir, System.tmp_dir!())
    log_dir = resolved_log_dir(opts)

    [
      tracked_output_dirs(),
      tmp_output_dirs(tmp_dir),
      log_output_dirs(log_dir)
    ]
    |> List.flatten()
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp list_limit(opts) do
    case Keyword.get(opts, :limit, @default_limit) do
      nil ->
        {:ok, nil}

      limit when is_integer(limit) and limit >= 0 ->
        {:ok, limit}

      limit ->
        error(:invalid_run_list_limit, "run list limit must be a non-negative integer",
          limit: limit
        )
    end
  end

  defp load_listed_runs(opts, limit) do
    opts
    |> discover_output_dirs()
    |> Enum.flat_map(&load_listed_run/1)
    |> Enum.sort_by(&{sort_timestamp(&1), &1.id, &1.output_dir}, :desc)
    |> maybe_limit(limit)
  end

  defp load_listed_run(output_dir) do
    case load_run(output_dir, :lenient) do
      {:ok, run} -> [run]
      nil -> []
    end
  end

  defp resolved_log_dir(opts) do
    case Keyword.fetch(opts, :log_dir) do
      {:ok, log_dir} -> log_dir
      :error -> safe_global_log_dir()
    end
  end

  defp safe_global_log_dir do
    TraceLog.global_log_dir()
  rescue
    _ -> nil
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
    |> Enum.reduce(MapSet.new(), fn line, acc ->
      case Jason.decode(line) do
        {:ok, %{"output_dir" => output_dir}} when is_binary(output_dir) ->
          MapSet.put(acc, output_dir)

        _ ->
          acc
      end
    end)
    |> MapSet.to_list()
  rescue
    _ -> []
  end

  defp run_dir?(output_dir) when is_binary(output_dir) do
    File.exists?(Path.join(output_dir, ArtifactLayout.manifest_file())) ||
      File.exists?(Path.join(output_dir, TraceLog.summary_file()))
  end

  defp run_dir?(_), do: false

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
    do:
      error(:run_artifacts_missing, "run artifacts not found: #{output_dir}",
        output_dir: output_dir
      )

  defp ensure_run_artifacts(_output_dir, _manifest, _summary, _contract), do: :ok

  defp derive_status(manifest, summary) do
    manifest_status = manifest_value(manifest, "status")
    summary_status = manifest_value(summary, "status")

    with :ok <- validate_status(manifest_status),
         :ok <- validate_status(summary_status) do
      case preferred_status(manifest_status, summary_status) do
        nil ->
          error(:run_status_missing, "run status is missing")

        status ->
          {:ok, status}
      end
    end
  end

  defp preferred_status(_manifest_status, summary_status)
       when summary_status in @terminal_statuses,
       do: summary_status

  defp preferred_status(manifest_status, summary_status), do: manifest_status || summary_status

  defp validate_status(nil), do: :ok
  defp validate_status(status) when status in @known_statuses, do: :ok

  defp validate_status(status) do
    error(:run_status_invalid, "unknown run status: #{inspect(status)}", status: status)
  end

  defp read_json_optional(path) do
    if File.exists?(path), do: read_json_file(path), else: {:ok, nil}
  end

  defp read_json_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- decode_json_object(body, path) do
      {:ok, decoded}
    else
      {:error, %Error{} = reason} ->
        {:error, reason}

      {:error, reason} ->
        error(
          :run_artifact_read_error,
          "failed to read #{path}: #{:file.format_error(reason)}",
          path: path
        )
    end
  end

  defp decode_json_object(body, path) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, decoded}

      {:ok, _decoded} ->
        error(:run_artifact_invalid, "expected JSON object at #{path}", path: path)

      {:error, reason} ->
        error(
          :run_artifact_decode_error,
          "failed to decode #{path}: #{Exception.message(reason)}",
          path: path
        )
    end
  end

  defp error(category, message, details \\ %{}) do
    reason = Map.merge(%{category: category, message: message}, Map.new(details))
    {:error, Error.from_reason(reason)}
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
        manifest_value(manifest, "workspace_root") ||
          manifest_value(summary, "workspace_root") ||
          manifest_value(contract, "workspace_root"),
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
