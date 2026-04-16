defmodule Thinktank.ProgressTest do
  use ExUnit.Case, async: true

  alias Thinktank.Progress

  test "emit normalizes payload keys for arity-2 callbacks" do
    parent = self()

    assert :ok =
             Progress.emit(
               [
                 progress_callback: fn event, attrs ->
                   send(parent, {:progress, event, attrs})
                 end
               ],
               :bootstrap_started,
               %{output_dir: "/tmp/run", nested: %{planned_agents: ["systems"]}}
             )

    assert_receive {:progress, "bootstrap_started",
                    %{"output_dir" => "/tmp/run", "nested" => %{"planned_agents" => ["systems"]}}}
  end

  test "emit folds the event into the payload for arity-1 callbacks" do
    parent = self()

    assert :ok =
             Progress.emit(
               [
                 progress_callback: fn attrs ->
                   send(parent, {:progress, attrs})
                 end
               ],
               :agent_finished,
               %{agent_name: "systems", status: "ok"}
             )

    assert_receive {:progress,
                    %{"event" => "agent_finished", "agent_name" => "systems", "status" => "ok"}}
  end

  test "phase mapping and trace path stay centralized" do
    assert Progress.phase_for_event("agents_started") == "running_agents"
    assert Progress.phase_for_event(:run_completed) == "finalizing"
    assert Progress.phase_for_event("unknown") == nil
    assert Progress.trace_events_path("tmp/run") == Path.expand("tmp/run/trace/events.jsonl")
  end
end
