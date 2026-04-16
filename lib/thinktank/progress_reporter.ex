defmodule Thinktank.ProgressReporter do
  @moduledoc """
  Emits newline-delimited JSON progress events to stderr for `--json` runs.
  """

  alias Thinktank.Progress

  @default_heartbeat_ms 5_000
  @type reporter :: pid() | nil

  @spec start(keyword()) :: reporter()
  def start(opts) do
    parent = self()
    ref = make_ref()
    output_dir = Path.expand(Keyword.fetch!(opts, :output_dir))

    state = %{
      bench: Keyword.fetch!(opts, :bench),
      output_dir: output_dir,
      trace_events: Progress.trace_events_path(output_dir),
      phase: "initializing",
      total_agents: 0,
      completed_agents: 0,
      failed_agents: 0,
      heartbeat_ms: heartbeat_ms(Keyword.get(opts, :heartbeat_ms)),
      emit: Keyword.fetch!(opts, :emit)
    }

    pid =
      spawn(fn ->
        Process.monitor(parent)

        emit(state, "phase", %{"trace_events" => state.trace_events})
        emit(state, "heartbeat", %{})
        send(parent, {ref, :ready})
        loop(state, parent)
      end)

    receive do
      {^ref, :ready} -> pid
    after
      100 -> pid
    end
  end

  @spec notify(reporter(), String.t(), map()) :: :ok
  def notify(nil, _event, _attrs), do: :ok

  def notify(pid, event, attrs) when is_pid(pid) and is_binary(event) and is_map(attrs) do
    send(pid, {:progress, event, attrs})
    :ok
  end

  @spec callback(reporter()) :: (String.t(), map() -> :ok)
  def callback(reporter) do
    fn event, attrs -> notify(reporter, event, attrs) end
  end

  @spec stop(reporter()) :: :ok
  def stop(nil), do: :ok

  def stop(pid) when is_pid(pid) do
    ref = make_ref()
    send(pid, {:stop, self(), ref})

    receive do
      {^ref, :stopped} -> :ok
    after
      100 -> :ok
    end
  end

  defp loop(state, parent) do
    receive do
      {:progress, event, attrs} ->
        state = handle_event(state, event, attrs)
        loop(state, parent)

      {:DOWN, _ref, :process, ^parent, _reason} ->
        :ok

      {:stop, caller, ref} ->
        send(caller, {ref, :stopped})
        :ok
    after
      state.heartbeat_ms ->
        emit(state, "heartbeat", %{})
        loop(state, parent)
    end
  end

  defp handle_event(state, event, attrs) do
    phase = attrs["phase"] || Progress.phase_for_event(event)

    next_state =
      state
      |> maybe_put_counts(event, attrs)
      |> maybe_record_agent_completion(event, attrs["status"])
      |> maybe_put_phase(phase)

    maybe_emit_phase(next_state, state.phase, phase, attrs)
    maybe_emit_agent_completion(next_state, event, attrs)
    next_state
  end

  defp maybe_put_counts(state, "agents_started", attrs) do
    case attrs["total_agents"] || attrs["planned_agent_count"] do
      total_agents when is_integer(total_agents) ->
        state
        |> Map.put(:total_agents, total_agents)
        |> Map.put(:completed_agents, 0)
        |> Map.put(:failed_agents, 0)

      _ ->
        state
    end
  end

  defp maybe_put_counts(state, _event, _attrs), do: state

  defp maybe_record_agent_completion(%{phase: "running_agents"} = state, "agent_finished", status) do
    failed_agents = if status == "error", do: state.failed_agents + 1, else: state.failed_agents

    %{state | completed_agents: state.completed_agents + 1, failed_agents: failed_agents}
  end

  defp maybe_record_agent_completion(state, _event, _status), do: state

  defp maybe_put_phase(state, nil), do: state
  defp maybe_put_phase(state, phase), do: Map.put(state, :phase, phase)

  defp maybe_emit_phase(_state, previous_phase, phase, _attrs)
       when is_nil(phase) or previous_phase == phase,
       do: :ok

  defp maybe_emit_phase(state, _previous_phase, _phase, attrs) do
    emit(state, "phase", attrs)
  end

  defp maybe_emit_agent_completion(%{phase: "running_agents"} = state, "agent_finished", attrs) do
    emit(state, "agent_finished", attrs)
  end

  defp maybe_emit_agent_completion(_state, _event, _attrs), do: :ok

  defp emit(state, kind, attrs) do
    payload =
      %{
        "type" => "progress",
        "kind" => kind,
        "phase" => state.phase,
        "bench" => state.bench,
        "output_dir" => state.output_dir
      }
      |> maybe_put(
        "trace_events",
        state.trace_events,
        kind == "phase" and state.phase == "initializing"
      )
      |> maybe_put("total_agents", state.total_agents, state.total_agents > 0)
      |> maybe_put("completed_agents", state.completed_agents, state.total_agents > 0)
      |> maybe_put("failed_agents", state.failed_agents, state.failed_agents > 0)
      |> Map.merge(attrs)

    safe_emit(state.emit, payload)
  end

  defp safe_emit(emit, payload) do
    emit.(payload)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  defp heartbeat_ms(value) when is_integer(value) and value > 0, do: value

  defp heartbeat_ms(_value) do
    case System.get_env("THINKTANK_PROGRESS_HEARTBEAT_MS") do
      nil ->
        @default_heartbeat_ms

      value ->
        case Integer.parse(value) do
          {ms, ""} when ms > 0 -> ms
          _ -> @default_heartbeat_ms
        end
    end
  end
end
