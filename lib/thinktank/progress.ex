defmodule Thinktank.Progress do
  @moduledoc false

  alias Thinktank.TraceLog

  @type event :: String.t() | atom()

  @spec emit(keyword(), event(), map()) :: :ok
  def emit(opts, event, attrs) when is_list(opts) and is_map(attrs) do
    callback = Keyword.get(opts, :progress_callback) || Keyword.get(opts, :progress)
    event = to_string(event)
    attrs = stringify_keys(attrs)

    case callback do
      fun when is_function(fun, 2) ->
        invoke(fun, event, attrs)

      fun when is_function(fun, 1) ->
        invoke(fun, Map.put(attrs, "event", event))

      _ ->
        :ok
    end
  end

  @spec phase_for_event(event()) :: String.t() | nil
  def phase_for_event("bootstrap_started"), do: "initializing"
  def phase_for_event("agents_started"), do: "running_agents"
  def phase_for_event("agent_started"), do: "running_agents"
  def phase_for_event("agent_finished"), do: "running_agents"
  def phase_for_event("synthesis_started"), do: "synthesizing"
  def phase_for_event("run_completed"), do: "finalizing"
  def phase_for_event(event) when is_atom(event), do: phase_for_event(Atom.to_string(event))
  def phase_for_event(_event), do: nil

  @spec trace_events_path(Path.t()) :: String.t()
  def trace_events_path(output_dir) when is_binary(output_dir) do
    Path.join(Path.expand(output_dir), TraceLog.events_file())
  end

  defp invoke(fun, payload) do
    fun.(payload)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp invoke(fun, event, attrs) do
    fun.(event, attrs)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), normalize_value(value)}
    end)
  end

  defp normalize_value(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> stringify_keys()
  end

  defp normalize_value(value) when is_map(value), do: stringify_keys(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value
end
