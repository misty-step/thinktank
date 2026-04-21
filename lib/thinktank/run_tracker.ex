defmodule Thinktank.RunTracker do
  @moduledoc """
  Tracks active runs so shutdown can finalize durable artifacts.
  """

  require Logger

  alias Thinktank.{RunStore, TraceLog}

  @table :thinktank_run_tracker

  @doc false
  @spec table_name() :: atom()
  def table_name, do: @table

  @spec start(Path.t(), map()) :: :ok
  def start(output_dir, attrs \\ %{}) when is_binary(output_dir) and is_map(attrs) do
    :ets.insert(table(), {canonical_output_dir(output_dir), normalize(attrs)})
    :ok
  end

  @spec finish(Path.t(), String.t(), map()) :: :ok
  def finish(output_dir, status, attrs \\ %{})
      when is_binary(output_dir) and is_binary(status) and is_map(attrs) do
    canonical_output_dir = canonical_output_dir(output_dir)

    case :ets.lookup(table(), canonical_output_dir) do
      [{^canonical_output_dir, _attrs}] ->
        complete(canonical_output_dir, status, attrs)
        unregister(canonical_output_dir)

      [] ->
        :ok
    end
  end

  @spec unregister(Path.t()) :: :ok
  def unregister(output_dir) when is_binary(output_dir) do
    :ets.delete(table(), canonical_output_dir(output_dir))
    :ok
  end

  @spec active_runs() :: [{String.t(), map()}]
  def active_runs do
    :ets.tab2list(table())
  end

  @spec finalize_active_runs(atom() | String.t()) :: :ok
  def finalize_active_runs(reason \\ :application_shutdown) do
    shutdown_error = shutdown_error(reason)

    Enum.each(active_runs(), fn {output_dir, attrs} ->
      unregister(output_dir)

      safe_complete(output_dir, "partial", %{
        "bench" => attrs["bench"],
        "phase" => "shutdown",
        "error" => shutdown_error
      })
    end)

    :ok
  end

  defp complete(output_dir, status, attrs) do
    normalized_attrs =
      attrs
      |> normalize()
      |> Map.delete("status")

    if status == "partial" do
      RunStore.ensure_partial_summary(output_dir)
    end

    RunStore.complete_run(output_dir, status)
    RunStore.append_run_note(output_dir, "run completed with status=#{status}")

    TraceLog.record_event(
      output_dir,
      "run_completed",
      Map.put(normalized_attrs, "status", status)
    )
  end

  defp safe_complete(output_dir, status, attrs) do
    complete(output_dir, status, attrs)
  rescue
    error ->
      Logger.warning(
        "run finalization failed for #{Path.expand(output_dir)}: #{Exception.message(error)}"
      )

      :ok
  catch
    kind, reason ->
      Logger.warning(
        "run finalization failed for #{Path.expand(output_dir)}: #{inspect({kind, reason})}"
      )

      :ok
  end

  defp shutdown_error(reason) do
    %{
      "category" => "shutdown",
      "reason" => reason_to_string(reason),
      "message" => "ThinkTank shut down before the run completed."
    }
  end

  defp reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason), do: inspect(reason)

  defp canonical_output_dir(output_dir), do: output_dir |> Path.expand()

  defp table do
    case :ets.whereis(table_name()) do
      :undefined ->
        try do
          :ets.new(table_name(), [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> table_name()
        end

      _ ->
        table_name()
    end
  end

  defp normalize(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> normalize()
  end

  defp normalize(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), normalize(nested)} end)
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value
end
