defmodule Thinktank.TraceLog do
  @moduledoc """
  Durable local trace/event log for ThinkTank runs.
  """

  require Logger

  @events_file "trace/events.jsonl"
  @summary_file "trace/summary.json"
  @lock_table :thinktank_trace_log_locks
  @default_lock_timeout_ms 250
  @lock_retry_delay_ms 1

  @doc false
  @spec lock_table_name() :: atom()
  def lock_table_name, do: @lock_table

  @spec init_run(Path.t(), map()) :: :ok
  def init_run(output_dir, attrs \\ %{}) do
    best_effort(output_dir, "init_run", %{}, fn ->
      ensure_trace_dir!(output_dir)
      ensure_file!(events_path(output_dir))
      write_summary(output_dir, Map.merge(summary_defaults(output_dir), normalize(attrs)))
    end)
  end

  @spec record_event(Path.t(), String.t(), map()) :: :ok
  def record_event(output_dir, event, attrs \\ %{}) when is_binary(event) do
    best_effort(output_dir, "record_event", %{"event" => event}, fn ->
      ensure_initialized(output_dir)

      record =
        attrs
        |> normalize()
        |> Map.merge(%{
          "event" => event,
          "run_id" => run_id(output_dir),
          "output_dir" => Path.expand(output_dir),
          "timestamp" => now_iso8601()
        })

      append_jsonl(events_path(output_dir), record)
      append_global_jsonl(record)
    end)
  end

  @spec record_global_event(String.t(), map()) :: :ok
  def record_global_event(event, attrs \\ %{}) when is_binary(event) do
    attrs
    |> normalize()
    |> Map.put("event", event)
    |> Map.put_new("timestamp", now_iso8601())
    |> normalize_global_record()
    |> append_global_jsonl()
  rescue
    error ->
      Logger.warning(
        "trace log record_global_event failed for #{event}: #{Exception.message(error)}"
      )

      :ok
  catch
    kind, reason ->
      Logger.warning(
        "trace log record_global_event failed for #{event}: #{inspect({kind, reason})}"
      )

      :ok
  end

  @spec complete_run(Path.t(), map()) :: :ok
  def complete_run(output_dir, attrs \\ %{}) do
    best_effort(output_dir, "complete_run", %{}, fn ->
      ensure_initialized(output_dir)
      update_summary(output_dir, &Map.merge(&1, normalize(attrs)))
    end)
  end

  @spec events_file() :: String.t()
  def events_file, do: @events_file

  @spec summary_file() :: String.t()
  def summary_file, do: @summary_file

  @spec global_log_dir() :: String.t() | nil
  def global_log_dir do
    case System.get_env("THINKTANK_LOG_DIR") do
      value when value in [nil, ""] ->
        default_log_dir()

      "off" ->
        nil

      value ->
        Path.expand(value)
    end
  end

  defp ensure_initialized(output_dir) do
    unless File.exists?(summary_path(output_dir)) do
      init_run(output_dir)
    end
  end

  defp summary_defaults(output_dir) do
    %{
      "version" => 1,
      "run_id" => run_id(output_dir),
      "output_dir" => Path.expand(output_dir),
      "status" => "running",
      "trace_events_file" => @events_file,
      "global_log_dir" => global_log_dir(),
      "dropped_events" => 0
    }
  end

  defp update_summary(output_dir, fun) do
    path = summary_path(output_dir)

    with_file_lock(path, fn ->
      current =
        if File.exists?(path) do
          path |> File.read!() |> Jason.decode!()
        else
          summary_defaults(output_dir)
        end

      write_json(path, fun.(current))
    end)
  end

  defp write_summary(output_dir, summary) do
    summary_path(output_dir)
    |> write_json(summary)
  end

  defp append_jsonl(path, record) do
    with_file_lock(path, fn ->
      ensure_private_parent!(path)
      created? = not File.exists?(path)
      File.write!(path, Jason.encode!(record) <> "\n", [:append])

      if created? do
        File.chmod!(path, 0o600)
      end
    end)
  end

  defp append_global_jsonl(record) do
    case global_log_path(record["timestamp"]) do
      nil ->
        :ok

      path ->
        try do
          append_jsonl(path, record)
        rescue
          _ -> :ok
        end
    end
  end

  defp normalize_global_record(%{"output_dir" => output_dir} = record)
       when is_binary(output_dir) do
    expanded = Path.expand(output_dir)

    record
    |> Map.put("output_dir", expanded)
    |> Map.put_new("run_id", run_id(expanded))
  end

  defp normalize_global_record(record), do: record

  defp with_file_lock(path, fun) do
    key = {__MODULE__, Path.expand(path)}
    acquire_lock(key, System.monotonic_time(:millisecond) + lock_timeout_ms())

    try do
      fun.()
    after
      release_lock(key)
    end
  end

  defp ensure_trace_dir!(output_dir) do
    dir = Path.join(output_dir, "trace")
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    dir
  end

  defp ensure_file!(path) do
    ensure_private_parent!(path)
    File.write!(path, "", [:append])
    File.chmod!(path, 0o600)
    :ok
  end

  defp write_json(path, data) do
    tmp = path <> ".tmp"
    ensure_private_parent!(path)
    File.write!(tmp, Jason.encode!(normalize(data), pretty: true))
    File.rename!(tmp, path)
    File.chmod!(path, 0o600)
    :ok
  end

  defp global_log_path(timestamp) do
    case global_log_dir() do
      nil ->
        nil

      dir ->
        date =
          case DateTime.from_iso8601(timestamp) do
            {:ok, datetime, _offset} -> DateTime.to_date(datetime)
            _ -> Date.utc_today()
          end
          |> Date.to_iso8601()

        Path.join(dir, "#{date}.jsonl")
    end
  end

  defp default_log_dir do
    base =
      System.get_env("XDG_STATE_HOME") ||
        Path.join(System.user_home!(), ".local/state")

    Path.join(base, "thinktank/logs")
  end

  defp ensure_private_parent!(path) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    dir
  end

  defp ensure_lock_table do
    case :ets.whereis(lock_table_name()) do
      :undefined ->
        try do
          :ets.new(lock_table_name(), [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          ArgumentError -> lock_table_name()
        end

      _ ->
        lock_table_name()
    end
  end

  defp acquire_lock(key, deadline_ms) do
    table = ensure_lock_table()

    case :ets.insert_new(table, {key, self()}) do
      true ->
        :ok

      false ->
        recycle_or_wait(table, key, deadline_ms)
        acquire_lock(key, deadline_ms)
    end
  end

  defp release_lock(key) do
    table = ensure_lock_table()

    case :ets.lookup(table, key) do
      [{^key, owner}] when owner == self() ->
        :ets.delete(table, key)
        :ok

      _ ->
        :ok
    end
  end

  defp events_path(output_dir), do: Path.join(output_dir, @events_file)
  defp summary_path(output_dir), do: Path.join(output_dir, @summary_file)

  defp run_id(output_dir) do
    output_dir
    |> Path.expand()
    |> Path.basename()
  end

  defp now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp best_effort(output_dir, operation, details, fun) do
    fun.()
  rescue
    error ->
      context = log_context(output_dir, details)
      message = Exception.message(error)
      record_dropped_event(output_dir, operation, details, message)

      Logger.warning(
        "trace log #{operation} failed for #{Path.expand(output_dir)} (#{context}): #{message}"
      )

      :ok
  catch
    kind, reason ->
      context = log_context(output_dir, details)
      message = inspect({kind, reason})
      record_dropped_event(output_dir, operation, details, message)

      Logger.warning(
        "trace log #{operation} failed for #{Path.expand(output_dir)} (#{context}): #{message}"
      )

      :ok
  end

  defp log_context(output_dir, details) do
    [%{"run_id" => run_id(output_dir)} | [normalize(details)]]
    |> Enum.reduce(%{}, &Map.merge/2)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp record_dropped_event(output_dir, operation, details, message) do
    path = summary_path(output_dir)

    with_file_lock(path, fn ->
      current = read_summary_or_default(path, output_dir)

      summary =
        current
        |> Map.update("dropped_events", 1, &(&1 + 1))
        |> Map.put("last_trace_error", %{
          "operation" => operation,
          "details" => normalize(details),
          "message" => message,
          "timestamp" => now_iso8601()
        })

      write_json(path, summary)
    end)
  rescue
    _ -> :ok
  end

  defp recycle_or_wait(table, key, deadline_ms) do
    if System.monotonic_time(:millisecond) >= deadline_ms do
      raise "timed out waiting for trace log lock"
    end

    case :ets.lookup(table, key) do
      [{^key, owner}] -> maybe_recycle_stale_lock(table, key, owner)
      _ -> Process.sleep(@lock_retry_delay_ms)
    end
  end

  defp maybe_recycle_stale_lock(table, key, owner) do
    if is_pid(owner) and not Process.alive?(owner) do
      :ets.delete(table, key)
    else
      Process.sleep(@lock_retry_delay_ms)
    end
  end

  defp lock_timeout_ms do
    case System.get_env("THINKTANK_TRACE_LOCK_TIMEOUT_MS") do
      nil ->
        @default_lock_timeout_ms

      value ->
        case Integer.parse(value) do
          {timeout_ms, ""} when timeout_ms >= 0 -> timeout_ms
          _ -> @default_lock_timeout_ms
        end
    end
  end

  defp read_summary_or_default(path, output_dir) do
    case File.read(path) do
      {:ok, body} -> decode_summary_or_default(body, output_dir)
      _ -> summary_defaults(output_dir)
    end
  end

  defp decode_summary_or_default(body, output_dir) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> decoded
      _ -> summary_defaults(output_dir)
    end
  end

  defp normalize(%_{} = value) do
    value
    |> Map.from_struct()
    |> normalize()
  end

  defp normalize(%{} = value) do
    value
    |> Enum.map(fn {key, entry} -> {to_string(key), normalize(entry)} end)
    |> Enum.into(%{})
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp normalize(nil), do: nil
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value), do: inspect(value)
end
